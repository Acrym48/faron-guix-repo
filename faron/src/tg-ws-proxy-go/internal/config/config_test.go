package config

import (
	"reflect"
	"testing"
)

func TestParseDcIpList(t *testing.T) {
	m, err := ParseDcIpList([]string{"2:149.154.167.220", "4:1.2.3.4"})
	if err != nil {
		t.Fatal(err)
	}
	want := map[int]string{2: "149.154.167.220", 4: "1.2.3.4"}
	if !reflect.DeepEqual(m, want) {
		t.Errorf("got %v want %v", m, want)
	}
}

func TestParseDcIpListLastWins(t *testing.T) {
	m, err := ParseDcIpList([]string{"2:1.1.1.1", "2:2.2.2.2"})
	if err != nil {
		t.Fatal(err)
	}
	if m[2] != "2.2.2.2" {
		t.Errorf("got %v", m)
	}
}

func TestParseDcIpListRejectsMissingSeparator(t *testing.T) {
	if _, err := ParseDcIpList([]string{"2-1.2.3.4"}); err == nil {
		t.Fatal("expected error")
	}
}

func TestParseDcIpListRejectsShortFormIPv4(t *testing.T) {
	for _, entry := range []string{"2:149.154", "2:1.2.3.4.5", "2:999.1.1.1", "2:abc"} {
		if _, err := ParseDcIpList([]string{entry}); err == nil {
			t.Errorf("expected error for %q", entry)
		}
	}
}

func TestParseDcIpListRejectsNonNumericDC(t *testing.T) {
	if _, err := ParseDcIpList([]string{"x:1.2.3.4"}); err == nil {
		t.Fatal("expected error")
	}
}

func TestCoerceDomainListSplitsSeparators(t *testing.T) {
	got := CoerceDomainList([]string{"a.com, b.com; c.com d.com"})
	want := []string{"a.com", "b.com", "c.com", "d.com"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v want %v", got, want)
	}
}

func TestCoerceDomainListDedupesCaseInsensitive(t *testing.T) {
	got := CoerceDomainList([]string{"A.com", "a.com"})
	if !reflect.DeepEqual(got, []string{"A.com"}) {
		t.Errorf("got %v", got)
	}
}

func TestCoerceDomainListFlattensSequences(t *testing.T) {
	got := CoerceDomainList([]string{"a.com b.com"})
	if !reflect.DeepEqual(got, []string{"a.com", "b.com"}) {
		t.Errorf("got %v", got)
	}
}

func TestIsValidDomainAcceptsOrdinary(t *testing.T) {
	for _, d := range []string{"example.com", "a-b.co.uk", "x.io"} {
		if !IsValidDomain(d) {
			t.Errorf("rejected %q", d)
		}
	}
}

func TestIsValidDomainRejectsMalformed(t *testing.T) {
	long := "a." + repeat("b", 64)
	huge := repeat("a", 250) + ".com"
	for _, d := range []string{
		"", "nodot", ".leading.com", "trailing.com.",
		"-bad.com", "bad-.com", "a..com", "a.1",
		long, huge,
	} {
		if IsValidDomain(d) {
			t.Errorf("accepted %q", d)
		}
	}
}

func TestNormalizeDomainPool(t *testing.T) {
	got := NormalizeDomainPool([]string{"B.com ", "b.com", "nodot", "a.com"})
	want := []string{"b.com", "a.com"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v want %v", got, want)
	}
}

func TestDecodedDefaultsAreValidAndUnique(t *testing.T) {
	domains := DefaultCfDomains()
	if len(domains) == 0 {
		t.Fatal("no default domains")
	}
	seen := make(map[string]struct{})
	for _, d := range domains {
		if !IsValidDomain(d) {
			t.Errorf("invalid default domain %q", d)
		}
		if _, dup := seen[d]; dup {
			t.Errorf("duplicate default domain %q", d)
		}
		seen[d] = struct{}{}
	}
}

func TestDecodeCfDomain(t *testing.T) {
	// The ".co.uk" suffix is produced from the ".com" family, and the body
	// is a Caesar shift by the number of alphabetic characters.
	got := DecodeCfDomain("virkgj.com")
	if !IsValidDomain(got) {
		t.Errorf("decoded %q -> %q is invalid", "virkgj.com", got)
	}
	if len(got) < len("virkgj")+len(".co.uk") || got[len(got)-6:] != ".co.uk" {
		t.Errorf("unexpected decoded domain %q", got)
	}
}

func repeat(s string, n int) string {
	out := make([]byte, 0, len(s)*n)
	for i := 0; i < n; i++ {
		out = append(out, s...)
	}
	return string(out)
}
