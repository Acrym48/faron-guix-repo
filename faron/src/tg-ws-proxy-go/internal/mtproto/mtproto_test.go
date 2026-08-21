package mtproto

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"testing"
)

// buildClientHandshake mimics a TDesktop client using a dd/ee proxy secret:
// bytes [8:56] are the RAW prekey+iv, and only bytes [56:64] are the
// ciphertext tail (proto tag + dc idx + padding) XORed with the keystream.
func buildClientHandshake(secret []byte, dcIdx int16, protoTag []byte) []byte {
	prekey := make([]byte, PrekeyLen)
	iv := make([]byte, IVLen)
	for i := range prekey {
		prekey[i] = byte(i*7 + 1)
	}
	for i := range iv {
		iv[i] = byte(i*3 + 5)
	}

	h := sha256.New()
	h.Write(prekey)
	h.Write(secret)
	decKey := h.Sum(nil)

	stream := NewCTR(decKey, iv)

	// raw 64-byte init: [8:56] = prekey+iv verbatim
	raw := make([]byte, HandshakeLen)
	for i := range raw {
		raw[i] = byte(i*11 + 3)
	}
	copy(raw[SkipLen:], prekey)
	copy(raw[SkipLen+PrekeyLen:], iv)

	// full keystream over the raw bytes
	enc := make([]byte, HandshakeLen)
	stream.XORKeyStream(enc, raw)
	// keystream bounds for [56:64]
	keystreamTail := make([]byte, 8)
	for i := 56; i < 64; i++ {
		keystreamTail[i-56] = enc[i] ^ raw[i]
	}

	tailPlain := make([]byte, 8)
	copy(tailPlain, protoTag)
	binary.LittleEndian.PutUint16(tailPlain[4:6], uint16(dcIdx))

	out := make([]byte, HandshakeLen)
	copy(out, raw)
	for i := 0; i < 8; i++ {
		out[ProtoTagPos+i] = tailPlain[i] ^ keystreamTail[i]
	}
	return out
}

func TestTryHandshakeRoundTrip(t *testing.T) {
	secret := bytes.Repeat([]byte{0xAB}, 16)
	cases := []struct {
		dc      int16
		isMedia bool
		tag     []byte
	}{
		{2, false, ProtoTagAbridged},
		{4, false, ProtoTagIntermediate},
		{5, true, ProtoTagSecure},
		{3, true, ProtoTagAbridged},
	}
	for _, c := range cases {
		dcIdx := c.dc
		if c.isMedia {
			dcIdx = -dcIdx
		}
		hs := buildClientHandshake(secret, dcIdx, c.tag)

		dc, isMedia, tag, _, err := TryHandshake(hs, secret)
		if err != nil {
			t.Fatalf("TryHandshake(%d): %v", c.dc, err)
		}
		wantDC := int(c.dc)
		if wantDC < 0 {
			wantDC = -wantDC
		}
		if dc != wantDC || isMedia != c.isMedia || !bytes.Equal(tag, c.tag) {
			t.Errorf("got dc=%d isMedia=%v tag=%x, want dc=%d isMedia=%v tag=%x",
				dc, isMedia, tag, wantDC, c.isMedia, c.tag)
		}
	}
}

func TestTryHandshakeWrongSecret(t *testing.T) {
	hs := buildClientHandshake(bytes.Repeat([]byte{0x01}, 16), 2, ProtoTagAbridged)
	if _, _, _, _, err := TryHandshake(hs, bytes.Repeat([]byte{0x02}, 16)); err == nil {
		t.Fatal("expected error for wrong secret")
	}
}

func TestTryHandshakeShortInput(t *testing.T) {
	if _, _, _, _, err := TryHandshake(make([]byte, 10), bytes.Repeat([]byte{0x01}, 16)); err != ErrShortHandshake {
		t.Fatalf("expected ErrShortHandshake, got %v", err)
	}
}

// TestGenerateRelayInitDecryptsToTagAndDC verifies that the relay peer (which
// consumes the init with the same forward AES-CTR stream) recovers the tag
// and DC index from bytes [56:64].
func TestGenerateRelayInitDecryptsToTagAndDC(t *testing.T) {
	dcIdx := int16(4)
	relayInit, err := GenerateRelayInit(ProtoTagIntermediate, dcIdx)
	if err != nil {
		t.Fatal(err)
	}
	if len(relayInit) != HandshakeLen {
		t.Fatalf("bad len %d", len(relayInit))
	}

	peer := NewCTR(relayInit[SkipLen:SkipLen+PrekeyLen],
		relayInit[SkipLen+PrekeyLen:SkipLen+PrekeyLen+IVLen])
	discard(peer, ProtoTagPos)

	tail := make([]byte, 8)
	copy(tail, relayInit[ProtoTagPos:])
	peer.XORKeyStream(tail, tail)

	if !bytes.Equal(tail[:4], ProtoTagIntermediate) {
		t.Errorf("proto tag mismatch: %x", tail[:4])
	}
	gotDC := int16(binary.LittleEndian.Uint16(tail[4:6]))
	if gotDC != dcIdx {
		t.Errorf("dc idx mismatch: got %d want %d", gotDC, dcIdx)
	}
}

// TestCryptoCtxPeerInvariants simulates the two peers (client and Telegram WS
// relay) decrypting with fresh streams and verifies BuildCryptoCtx streams
// are consistent with them on both directions.
func TestCryptoCtxPeerInvariants(t *testing.T) {
	secret := bytes.Repeat([]byte{0x11}, 16)
	relayInit, err := GenerateRelayInit(ProtoTagAbridged, 2)
	if err != nil {
		t.Fatal(err)
	}

	cltPrekeyIV := make([]byte, PrekeyLen+IVLen)
	for i := range cltPrekeyIV {
		cltPrekeyIV[i] = byte(i)
	}

	ctx := BuildCryptoCtx(cltPrekeyIV, secret, relayInit)
	payload := []byte("hello mtproto world, this is a test payload")

	// --- upstream direction (us -> relay) ---------------------------------
	ourCipher := make([]byte, len(payload))
	ctx.TgEnc.XORKeyStream(ourCipher, payload)
	// relay decrypts with the same forward stream, after consuming init
	relayPeer := NewCTR(relayInit[SkipLen:SkipLen+PrekeyLen],
		relayInit[SkipLen+PrekeyLen:SkipLen+PrekeyLen+IVLen])
	discard(relayPeer, 64)
	relayPlain := make([]byte, len(payload))
	relayPeer.XORKeyStream(relayPlain, ourCipher)
	if !bytes.Equal(relayPlain, payload) {
		t.Fatal("relay failed to decrypt our upstream ciphertext")
	}

	// --- downstream direction (relay -> us) -------------------------------
	// relay encrypts its reply with the reversed-prekey/iv stream (fresh)
	relayEnc := NewCTR(reverseBytes(relayInit[SkipLen : SkipLen+PrekeyLen+IVLen])[:KeyLen],
		reverseBytes(relayInit[SkipLen : SkipLen+PrekeyLen+IVLen])[KeyLen:])
	serverCipher := make([]byte, len(payload))
	relayEnc.XORKeyStream(serverCipher, payload)
	ourDown := make([]byte, len(payload))
	ctx.TgDec.XORKeyStream(ourDown, serverCipher)
	if !bytes.Equal(ourDown, payload) {
		t.Fatal("failed to decrypt relay downstream ciphertext")
	}

	// --- client direction -------------------------------------------------
	// client encrypts with CTR(SHA256(prekey+secret), iv) after its init
	cltPrekey := cltPrekeyIV[:PrekeyLen]
	cltIV := cltPrekeyIV[PrekeyLen:]
	h := sha256.New()
	h.Write(cltPrekey)
	h.Write(secret)
	cltPeer := NewCTR(h.Sum(nil), cltIV)
	discard(cltPeer, 64)
	cltCipher := make([]byte, len(payload))
	cltPeer.XORKeyStream(cltCipher, payload)
	ourUp := make([]byte, len(payload))
	ctx.CltDec.XORKeyStream(ourUp, cltCipher)
	if !bytes.Equal(ourUp, payload) {
		t.Fatal("failed to decrypt client upstream ciphertext")
	}

	// we encrypt the reply with the reversed client stream (fresh)
	reversed := reverseBytes(cltPrekeyIV)
	h2 := sha256.New()
	h2.Write(reversed[:PrekeyLen])
	h2.Write(secret)
	ourCipherReply := make([]byte, len(payload))
	ctx.CltEnc.XORKeyStream(ourCipherReply, payload)
	clientPeer := NewCTR(h2.Sum(nil), reversed[PrekeyLen:])
	clientPlain := make([]byte, len(payload))
	clientPeer.XORKeyStream(clientPlain, ourCipherReply)
	if !bytes.Equal(clientPlain, payload) {
		t.Fatal("client failed to decrypt our reply")
	}
}

func TestGenerateRelayInitReservedPadding(t *testing.T) {
	produced := make(map[[HandshakeLen]byte]struct{})
	for i := 0; i < 50; i++ {
		init, err := GenerateRelayInit(ProtoTagAbridged, 2)
		if err != nil {
			t.Fatal(err)
		}
		var key [HandshakeLen]byte
		copy(key[:], init)
		produced[key] = struct{}{}
	}
	if len(produced) < 40 {
		t.Fatalf("insufficient entropy in generated init packets: %d unique/50", len(produced))
	}
	// first byte must never collide with reserved start 0xEF
	for i := 0; i < 200; i++ {
		init, _ := GenerateRelayInit(ProtoTagAbridged, 2)
		if init[0] == 0xEF {
			t.Fatal("reserved first byte produced")
		}
	}
}
