// Package mtproto implements the MTProto obfuscated transport handshake
// constants and helpers used by the Windows proxy.
package mtproto

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"errors"
)

const (
	HandshakeLen = 64
	SkipLen      = 8
	PrekeyLen    = 32
	KeyLen       = 32
	IVLen        = 16
	ProtoTagPos  = 56
	DcIdxPos     = 60
)

var (
	ProtoTagAbridged     = []byte{0xef, 0xef, 0xef, 0xef}
	ProtoTagIntermediate = []byte{0xee, 0xee, 0xee, 0xee}
	ProtoTagSecure       = []byte{0xdd, 0xdd, 0xdd, 0xdd}
)

const (
	ProtoAbridgedInt           uint32 = 0xEFEFEFEF
	ProtoIntermediateInt       uint32 = 0xEEEEEEEE
	ProtoPaddedIntermediateInt uint32 = 0xDDDDDDDD
)

var reservedStarts = [][]byte{
	[]byte("HEAD"),
	[]byte("POST"),
	[]byte("GET "),
	ProtoTagIntermediate,
	ProtoTagSecure,
	{0x16, 0x03, 0x01, 0x02},
}

var reservedContinue = []byte{0, 0, 0, 0}

var (
	ErrShortHandshake = errors.New("handshake too short")
	ErrBadProtoTag    = errors.New("unrecognized transport proto tag")
)

// NewCTR builds an AES-CTR keystream stream over the given key/iv.
// NaN behavior mirrors `Cipher(algorithm, CTR(iv)).encryptor()` from
// the Python `cryptography` shim.
func NewCTR(key, iv []byte) cipher.Stream {
	block, err := aes.NewCipher(key)
	if err != nil {
		panic("mtproto: invalid AES key: " + err.Error())
	}
	if len(iv) != aes.BlockSize {
		panic("mtproto: invalid AES-CTR IV length")
	}
	return cipher.NewCTR(block, iv)
}

func reverseBytes(in []byte) []byte {
	out := make([]byte, len(in))
	for i, b := range in {
		out[len(in)-1-i] = b
	}
	return out
}

func discard(stream cipher.Stream, n int) {
	buf := make([]byte, n)
	stream.XORKeyStream(buf, buf)
}

// TryHandshake validates the client obfuscated init packet and returns
// the parsed DC id / media flag / proto tag together with the encryption
// material needed to build the crypto context.
func TryHandshake(handshake, secret []byte) (dc int, isMedia bool, protoTag []byte, decPrekeyIV []byte, err error) {
	if len(handshake) < SkipLen+PrekeyLen+IVLen {
		return 0, false, nil, nil, ErrShortHandshake
	}
	decPrekeyIV = handshake[SkipLen : SkipLen+PrekeyLen+IVLen]
	decPrekey := decPrekeyIV[:PrekeyLen]
	decIV := decPrekeyIV[PrekeyLen:]

	h := sha256.New()
	h.Write(decPrekey)
	h.Write(secret)
	decKey := h.Sum(nil)

	dec := NewCTR(decKey, decIV)
	decrypted := make([]byte, len(handshake))
	dec.XORKeyStream(decrypted, handshake)

	gotTag := decrypted[ProtoTagPos : ProtoTagPos+4]
	switch {
	case bytes.Equal(gotTag, ProtoTagAbridged):
		protoTag = ProtoTagAbridged
	case bytes.Equal(gotTag, ProtoTagIntermediate):
		protoTag = ProtoTagIntermediate
	case bytes.Equal(gotTag, ProtoTagSecure):
		protoTag = ProtoTagSecure
	default:
		return 0, false, nil, nil, ErrBadProtoTag
	}

	dcIdx := int16(binary.LittleEndian.Uint16(decrypted[DcIdxPos : DcIdxPos+2]))
	dc = int(dcIdx)
	if dc < 0 {
		dc = -dc
	}
	isMedia = dcIdx < 0
	return dc, isMedia, protoTag, decPrekeyIV, nil
}

// GenerateRelayInit builds the 64-byte relay init packet that is sent to
// the upstream Telegram WebSocket endpoint. Mirrors `_generate_relay_init`.
func GenerateRelayInit(protoTag []byte, dcIdx int16) ([]byte, error) {
	rnd := make([]byte, HandshakeLen)
	for {
		if _, err := rand.Read(rnd); err != nil {
			return nil, err
		}
		if rnd[0] == 0xEF {
			continue
		}
		reserved := false
		for _, s := range reservedStarts {
			if bytes.HasPrefix(rnd, s) {
				reserved = true
				break
			}
		}
		if reserved {
			continue
		}
		if bytes.Equal(rnd[4:8], reservedContinue) {
			continue
		}
		break
	}

	enc := NewCTR(rnd[SkipLen:SkipLen+PrekeyLen],
		rnd[SkipLen+PrekeyLen:SkipLen+PrekeyLen+IVLen])

	encryptedFull := make([]byte, HandshakeLen)
	enc.XORKeyStream(encryptedFull, rnd)

	keystreamTail := make([]byte, 8)
	for i := 56; i < 64; i++ {
		keystreamTail[i-56] = encryptedFull[i] ^ rnd[i]
	}

	tailPlain := make([]byte, 8)
	copy(tailPlain, protoTag)
	binary.LittleEndian.PutUint16(tailPlain[4:6], uint16(dcIdx))
	if _, err := rand.Read(tailPlain[6:8]); err != nil {
		return nil, err
	}

	result := make([]byte, HandshakeLen)
	copy(result, rnd)
	for i := 0; i < 8; i++ {
		result[ProtoTagPos+i] = tailPlain[i] ^ keystreamTail[i]
	}
	return result, nil
}

// CryptoCtx holds the four AES-CTR streams that bridge the client ciphertext
// and the Telegram relay ciphertext.
//
//	ciphertext client -> CltDec -> plaintext -> TgEnc -> relay ciphertext
//	relay ciphertext   -> TgDec  -> plaintext -> CltEnc -> client ciphertext
type CryptoCtx struct {
	CltDec cipher.Stream
	CltEnc cipher.Stream
	TgEnc  cipher.Stream
	TgDec  cipher.Stream
}

// BuildCryptoCtx derives the four keystreams from the client prekey/iv and
// the generated relay init. Mirrors `_build_crypto_ctx`.
func BuildCryptoCtx(clientDecPrekeyIV, secret, relayInit []byte) *CryptoCtx {
	cltDecPrekey := clientDecPrekeyIV[:PrekeyLen]
	cltDecIV := clientDecPrekeyIV[PrekeyLen:]

	h := sha256.New()
	h.Write(cltDecPrekey)
	h.Write(secret)
	cltDecKey := h.Sum(nil)

	cltDec := NewCTR(cltDecKey, cltDecIV)
	discard(cltDec, 64)

	cltEncPrekeyIV := reverseBytes(clientDecPrekeyIV)
	h = sha256.New()
	h.Write(cltEncPrekeyIV[:PrekeyLen])
	h.Write(secret)
	cltEncKey := h.Sum(nil)
	cltEncIV := cltEncPrekeyIV[PrekeyLen:]
	cltEnc := NewCTR(cltEncKey, cltEncIV)

	relayEnc := NewCTR(relayInit[SkipLen:SkipLen+PrekeyLen],
		relayInit[SkipLen+PrekeyLen:SkipLen+PrekeyLen+IVLen])
	discard(relayEnc, 64)

	relayDecPrekeyIV := reverseBytes(
		relayInit[SkipLen : SkipLen+PrekeyLen+IVLen])
	relayDecKey := relayDecPrekeyIV[:KeyLen]
	relayDecIV := relayDecPrekeyIV[KeyLen:]
	relayDec := NewCTR(relayDecKey, relayDecIV)

	return &CryptoCtx{
		CltDec: cltDec,
		CltEnc: cltEnc,
		TgEnc:  relayEnc,
		TgDec:  relayDec,
	}
}
