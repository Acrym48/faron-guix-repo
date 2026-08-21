// Package splitter splits the relay-side MTProto transport ciphertext into
// individual transport packets so each packet maps to one WebSocket frame.
package splitter

import (
	"encoding/binary"

	"tg-ws-proxy-go/internal/mtproto"
)

const readChunkCap = 1 << 16

// MsgSplitter decodes the relay stream with AES-CTR to locate packet
// boundaries (abridged / intermediate transport framing) and slices the
// buffered ciphertext accordingly. Mirrors the Python `MsgSplitter`.
type MsgSplitter struct {
	dec       cipherStream
	proto     uint32
	cipherBuf []byte
	plainBuf  []byte
	disabled  bool
}

type cipherStream interface {
	XORKeyStream(dst, src []byte)
}

func NewMsgSplitter(relayInit []byte, proto uint32) (*MsgSplitter, error) {
	if len(relayInit) < 56 {
		return nil, errTooShort
	}
	dec := mtproto.NewCTR(relayInit[8:40], relayInit[40:56])
	scratch := make([]byte, 64)
	dec.XORKeyStream(scratch, scratch)
	return &MsgSplitter{dec: dec, proto: proto}, nil
}

var errTooShort = errNoPacket{}

// Split consumes a ciphertext chunk and returns zero or more complete
// transport packets. A trailing partial packet is buffered until it fills.
func (s *MsgSplitter) Split(chunk []byte) [][]byte {
	if len(chunk) == 0 {
		return nil
	}
	if s.disabled {
		return [][]byte{append([]byte(nil), chunk...)}
	}

	s.cipherBuf = append(s.cipherBuf, chunk...)
	decOut := make([]byte, len(chunk))
	s.dec.XORKeyStream(decOut, chunk)
	s.plainBuf = append(s.plainBuf, decOut...)

	var parts [][]byte
	offset := 0
	bufLen := len(s.cipherBuf)
	// Walk with an offset instead of deleting from the front so a single
	// trailing del keeps splitting amortized O(N) even for many small packets.
	for offset < bufLen {
		packetLen := s.nextPacketLen(offset, bufLen-offset)
		if packetLen < 0 {
			break
		}
		if packetLen == 0 {
			parts = append(parts, append([]byte(nil), s.cipherBuf[offset:]...))
			offset = bufLen
			s.disabled = true
			break
		}
		parts = append(parts, append([]byte(nil), s.cipherBuf[offset:offset+packetLen]...))
		offset += packetLen
	}

	if offset > 0 {
		s.cipherBuf = s.cipherBuf[offset:]
		s.plainBuf = s.plainBuf[offset:]
	}
	return parts
}

// Flush returns any buffered tail bytes once (during graceful shutdown).
func (s *MsgSplitter) Flush() []byte {
	if len(s.cipherBuf) == 0 {
		return nil
	}
	tail := append([]byte(nil), s.cipherBuf...)
	s.cipherBuf = nil
	s.plainBuf = nil
	return tail
}

// nextPacketLen returns the packet length at offset:
//   - >=1 complete packet,
//   - 0 to disable splitting (invalid zero-length packet),
//   - -1 when more bytes are needed.
func (s *MsgSplitter) nextPacketLen(offset, avail int) int {
	if avail <= 0 {
		return -1
	}
	switch s.proto {
	case mtproto.ProtoAbridgedInt:
		return s.nextAbridgedLen(offset, avail)
	case mtproto.ProtoIntermediateInt, mtproto.ProtoPaddedIntermediateInt:
		return s.nextIntermediateLen(offset, avail)
	default:
		return 0
	}
}

func (s *MsgSplitter) nextAbridgedLen(offset, avail int) int {
	first := s.plainBuf[offset]
	var payloadLen int
	if first == 0x7F || first == 0xFF {
		if avail < 4 {
			return -1
		}
		payloadLen = int(binary.LittleEndian.Uint32(s.plainBuf[offset+1:offset+4])) * 4
		packetLen := 4 + payloadLen
		if avail < packetLen {
			return -1
		}
		return packetLen
	}
	payloadLen = int(first&0x7F) * 4
	if payloadLen <= 0 {
		return 0
	}
	packetLen := 1 + payloadLen
	if avail < packetLen {
		return -1
	}
	return packetLen
}

func (s *MsgSplitter) nextIntermediateLen(offset, avail int) int {
	if avail < 4 {
		return -1
	}
	payloadLen := int(binary.LittleEndian.Uint32(s.plainBuf[offset:offset+4])) & 0x7FFFFFFF
	if payloadLen <= 0 {
		return 0
	}
	packetLen := 4 + payloadLen
	if avail < packetLen {
		return -1
	}
	return packetLen
}

type errNoPacket struct{}

func (errNoPacket) Error() string { return "mtproto splitter: packet too short" }
