package splitter

import (
	"bytes"
	"crypto/rand"
	"encoding/binary"
	"testing"

	"tg-ws-proxy-go/internal/mtproto"
)

func relayInit(t *testing.T) []byte {
	t.Helper()
	b := make([]byte, 64)
	if _, err := rand.Read(b); err != nil {
		t.Fatal(err)
	}
	return b
}

// encryptStream builds the relay ciphertext stream for a run of packets.
func encryptStream(t *testing.T, init []byte, packets ...[]byte) []byte {
	t.Helper()
	enc := mtproto.NewCTR(init[8:40], init[40:56])
	scratch := make([]byte, 64)
	enc.XORKeyStream(scratch, scratch)

	var joined []byte
	for _, p := range packets {
		joined = append(joined, p...)
	}
	out := make([]byte, len(joined))
	enc.XORKeyStream(out, joined)
	return out
}

func abridged(payload []byte) []byte {
	words := len(payload) / 4
	if words < 0x7F {
		return append([]byte{byte(words)}, payload...)
	}
	hdr := make([]byte, 4)
	hdr[0] = 0x7F
	binary.LittleEndian.PutUint32(hdr[1:4], uint32(words))
	return append(hdr, payload...)
}

func intermediate(payload []byte) []byte {
	hdr := make([]byte, 4)
	binary.LittleEndian.PutUint32(hdr, uint32(len(payload)))
	return append(hdr, payload...)
}

func splitAll(t *testing.T, init []byte, proto uint32, stream []byte, chunkSizes []int) ([][]byte, *MsgSplitter) {
	t.Helper()
	s, err := NewMsgSplitter(init, proto)
	if err != nil {
		t.Fatal(err)
	}
	var parts [][]byte
	if chunkSizes == nil {
		for _, p := range s.Split(stream) {
			parts = append(parts, p)
		}
	} else {
		off := 0
		for _, size := range chunkSizes {
			end := off + size
			if end > len(stream) {
				end = len(stream)
			}
			for _, p := range s.Split(stream[off:end]) {
				parts = append(parts, p)
			}
			off = end
		}
		for _, p := range s.Split(stream[off:]) {
			parts = append(parts, p)
		}
	}
	return parts, s
}

func TestAbridgedStreamSplitsIntoPackets(t *testing.T) {
	init := relayInit(t)
	packets := [][]byte{
		abridged(bytes.Repeat([]byte{'a'}, 4)),
		abridged(bytes.Repeat([]byte{'b'}, 16)),
		abridged(bytes.Repeat([]byte{'c'}, 40)),
	}
	stream := encryptStream(t, init, packets...)
	parts, _ := splitAll(t, init, mtproto.ProtoAbridgedInt, stream, nil)
	if len(parts) != 3 {
		t.Fatalf("got %d parts, want 3", len(parts))
	}
	if !bytes.Equal(bytes.Join(parts, nil), stream) {
		t.Fatal("parts do not reconstruct the stream")
	}
	wantLens := []int{5, 17, 41}
	for i, pl := range wantLens {
		if len(parts[i]) != pl {
			t.Errorf("part %d len=%d want %d", i, len(parts[i]), pl)
		}
	}
}

func TestIntermediateStreamSplitsIntoPackets(t *testing.T) {
	init := relayInit(t)
	packets := [][]byte{
		intermediate(bytes.Repeat([]byte{'a'}, 8)),
		intermediate(bytes.Repeat([]byte{'b'}, 12)),
	}
	stream := encryptStream(t, init, packets...)
	parts, _ := splitAll(t, init, mtproto.ProtoIntermediateInt, stream, nil)
	if len(parts) != 2 {
		t.Fatalf("got %d parts, want 2", len(parts))
	}
	if !bytes.Equal(bytes.Join(parts, nil), stream) {
		t.Fatal("parts do not reconstruct the stream")
	}
}

func TestPaddedIntermediateUsesIntermediateFraming(t *testing.T) {
	init := relayInit(t)
	packets := [][]byte{intermediate(bytes.Repeat([]byte{'z'}, 20))}
	stream := encryptStream(t, init, packets...)
	parts, _ := splitAll(t, init, mtproto.ProtoPaddedIntermediateInt, stream, nil)
	if len(parts) != 1 || !bytes.Equal(parts[0], stream) {
		t.Fatalf("padded intermediate got %d parts", len(parts))
	}
}

func TestPartialPacketIsBufferedUntilComplete(t *testing.T) {
	init := relayInit(t)
	pkt := abridged(bytes.Repeat([]byte{'a'}, 20))
	stream := encryptStream(t, init, pkt)
	chunkSizes := make([]int, len(pkt)-1)
	for i := range chunkSizes {
		chunkSizes[i] = 1
	}
	parts, _ := splitAll(t, init, mtproto.ProtoAbridgedInt, stream, chunkSizes)
	if len(parts) != 1 || !bytes.Equal(parts[0], stream) {
		t.Fatalf("partial buffering failed: %d parts", len(parts))
	}
}

func TestSplitPreservesStreamAcrossArbitraryChunking(t *testing.T) {
	init := relayInit(t)
	var packets [][]byte
	for i := 0; i < 8; i++ {
		packets = append(packets, intermediate(bytes.Repeat([]byte{byte(i)}, 16)))
	}
	stream := encryptStream(t, init, packets...)
	parts, _ := splitAll(t, init, mtproto.ProtoIntermediateInt, stream, []int{7, 3, 50, 11})
	if !bytes.Equal(bytes.Join(parts, nil), stream) {
		t.Fatal("stream not preserved")
	}
	if len(parts) != 8 {
		t.Fatalf("got %d parts, want 8", len(parts))
	}
}

func TestEmptyChunkYieldsNothing(t *testing.T) {
	s, err := NewMsgSplitter(relayInit(t), mtproto.ProtoIntermediateInt)
	if err != nil {
		t.Fatal(err)
	}
	if parts := s.Split(nil); len(parts) != 0 {
		t.Fatalf("expected no parts, got %d", len(parts))
	}
}

func TestZeroLengthPacketDisablesSplitting(t *testing.T) {
	init := relayInit(t)
	s, _ := NewMsgSplitter(init, mtproto.ProtoIntermediateInt)
	enc := mtproto.NewCTR(init[8:40], init[40:56])
	scratch := make([]byte, 64)
	enc.XORKeyStream(scratch, scratch)

	zero := make([]byte, 4)
	stream := make([]byte, 4+4)
	copy(stream, zero)
	copy(stream[4:], "tail")
	enc.XORKeyStream(stream, stream)

	parts := s.Split(stream)
	if len(parts) != 1 || !bytes.Equal(parts[0], stream) {
		t.Fatalf("zero-length packet handling failed: %d parts", len(parts))
	}
	if parts := s.Split([]byte("raw")); len(parts) != 1 || !bytes.Equal(parts[0], []byte("raw")) {
		t.Fatal("splitter not disabled after invalid packet")
	}
}

func TestFlushReturnsBufferedTailOnce(t *testing.T) {
	init := relayInit(t)
	s, _ := NewMsgSplitter(init, mtproto.ProtoIntermediateInt)
	enc := mtproto.NewCTR(init[8:40], init[40:56])
	scratch := make([]byte, 64)
	enc.XORKeyStream(scratch, scratch)

	pkt := intermediate(bytes.Repeat([]byte{'x'}, 32))
	partial := pkt[:10]
	stream := make([]byte, 10)
	copy(stream, partial)
	enc.XORKeyStream(stream, stream)

	if parts := s.Split(stream); len(parts) != 0 {
		t.Fatalf("expected no parts for partial, got %d", len(parts))
	}
	if tail := s.Flush(); !bytes.Equal(tail, stream) {
		t.Fatal("flush mismatch")
	}
	if tail := s.Flush(); len(tail) != 0 {
		t.Fatal("second flush should be empty")
	}
}
