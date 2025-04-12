module base64;

import std.stdio;
import std.range;

enum countBits (T) = T.sizeof * 8;

T ldb (T) (T src, uint start, uint nBits) {
    enum size = countBits!T;
    assert(start < size);
    assert(nBits <= size - start && nBits > 0);
    src <<= start;
    src >>= size - nBits;
    return src;
}

//------------------------------------------------------------------------------------------------------------------

struct SixBits {
    ubyte val;

    Base64Octet encode () {
        Base64Octet octet;
        leaveSwitch:
        final switch (val) {
            static foreach (k, v; zip(iota(0, 26), iota('A', 'Z'+1)) ) {
                case k: octet = v.makeBase64Octet; break leaveSwitch;
            }
            static foreach (k, v; zip(iota(26, 52), iota('a', 'z'+1)) ) {
                case k: octet = v.makeBase64Octet; break leaveSwitch;
            }
            static foreach (k, v; zip(iota(52, 62), iota('0', '9'+1)) ) {
                case k: octet = v.makeBase64Octet; break leaveSwitch;
            }
            case 62: octet = '+'.makeBase64Octet; break;
            case 63: octet = '/'.makeBase64Octet; break;
        }
        return octet;
    }
}

SixBits makeSixBits (ubyte b) {
    return SixBits(b);
}

struct Base64Octet {
    ubyte val;

    SixBits decode () {
        SixBits sixBits;
        leaveSwitch:
        final switch (val) {
            static foreach (k, v; zip(iota('A', 'Z'+1), iota(0, 26)) ) {
                case k: sixBits = v.makeSixBits; break leaveSwitch;
            }
            static foreach (k, v; zip(iota('a', 'z'+1), iota(26, 52)) ) {
                case k: sixBits = v.makeSixBits; break leaveSwitch;
            }
            static foreach (k, v; zip(iota('0', '9'+1), iota(52, 62)) ) {
                case k: sixBits = v.makeSixBits; break leaveSwitch;
            }
            case '+': sixBits = 62.makeSixBits; break;
            case '/': sixBits = 63.makeSixBits; break;
            case '=': break;
        }
        return sixBits;
    }
}

Base64Octet makeBase64Octet (ubyte b) {
    return Base64Octet(b);
}

//---------------------------------------------------------------------------------------------------------------

struct Triplet {
    ubyte[3] array;

    this (ubyte[3] array) {
        this.array = array;
    }

    this (ubyte[] slc) {
        assert(slc.length == 3);
        array[] = slc;
    }
    
    this (string str) {
        ubyte[] raw = cast(ubyte[]) str;
        this(raw);
    }

    Base64Quadruplet encode () {
        /// Convert 3-byte array to uint.
        uint n;
        foreach (b; array) {
            n |= b;
            n <<= 8;
        }

        /// Extract each 6-bit portion, encode the portions and store each encoding as a complete byte.
        Base64Quadruplet quadruplet;
        quadruplet.array[0] = (cast(ubyte) n.ldb(0, 6)).makeSixBits.encode;
        quadruplet.array[1] = (cast(ubyte) n.ldb(6, 6)).makeSixBits.encode;
        quadruplet.array[2] = (cast(ubyte) n.ldb(12, 6)).makeSixBits.encode;
        quadruplet.array[3] = (cast(ubyte) n.ldb(18, 6)).makeSixBits.encode;

        return quadruplet;
    }
}

struct Base64Quadruplet {
    Base64Octet[4] array;

    this (Base64Octet[4] array) {
        this.array = array;
    }

    this (Base64Octet[] array) {
        assert(array.length == 4);
        this.array[] = array[];
    }

    Triplet decode () {
        /// For each byte, decode to 6-bit value and store it in a uint.
        uint n;
        foreach (b; array) {
            n <<= 6;
            n |= b.decode.val;
        }
        n <<= 8; // Needed because shifting 6 bits at a time (due to decoding) 4 times is 24 bits, leaving 8 bits in the front.

        /// Now that each 6-bit segment is in the uint, extract the octets into an array.
        Triplet triplet;
        triplet.array[0] = cast(ubyte) n.ldb(0, 8);
        triplet.array[1] = cast(ubyte) n.ldb(8, 8);
        triplet.array[2] = cast(ubyte) n.ldb(16, 8);
        return triplet;
    }
}

//---------------------------------------------------------------------------------------------------------------

Base64Sequence encodeSequence (ubyte[] sequence) {
    auto sequenceLen = sequence.length;
    assert(sequenceLen > 0);

    uint rem = sequenceLen % 3;
    ubyte[] head = sequence[0..$ - rem];
    ubyte[] tail = sequence[$ - rem..$];

    Base64Octet[] octets;

    foreach (i; iota(0, head.length, 3)) {
        auto triplet = Triplet(head[i..i + 3]);
        auto quadruplet = triplet.encode;
        octets ~= quadruplet.array;
    }

    Triplet triplet;
    foreach (i, item; tail) {
        triplet.array[i] = item;
    }

    if (rem != 0) {
        Base64Quadruplet quadruplet;

        final switch (rem)
        {
            case 1:
                quadruplet = triplet.encode;
                quadruplet.array[2] = makeBase64Octet('=');
                quadruplet.array[3] = makeBase64Octet('=');
                break;
            case 2:
                quadruplet = triplet.encode;
                quadruplet.array[3] = makeBase64Octet('=');
                break;
        }

        foreach (o; quadruplet.array) {
            octets ~= o;
        }
    }

    return makeBase64Sequence(octets);
}

Base64Sequence encodeSequence (const(char[]) sequence) {
    auto seq = cast(ubyte[]) sequence;
    return seq.encodeSequence;
}

struct Base64Sequence {
    Base64Octet[] octets;
    uint padding;

    this (Base64Octet[] octets) {
        this.octets = octets;
    }

    this (ubyte[] array) {
        foreach (b; array) {
            switch (b)
            {
                static foreach (c; iota('A', 'Z'+1)) {
                    case c:
                }
                static foreach (c; iota('a', 'z'+1)) {
                    case c:
                }
                static foreach (c; iota('0', '9'+1)) {
                    case c:
                }
                case '+':
                case '/':
                case '=':
                    this.octets ~= makeBase64Octet(b);
                    break;
                default:
                    throw new Exception("Invalid Base64 character.");
            }
        }
    }

    this (string str) {
        this(cast(ubyte[]) str);
    }

    auto length () => octets.length;
    
    ubyte[] decodeSequence () {
        ubyte[] sequence;

        foreach (i; iota(0, octets.length - 4, 4)) {
            auto quadruplet = Base64Quadruplet(octets[i..i + 4]);
            auto triplet = quadruplet.decode;
            sequence ~= triplet.array;
        }

        auto quadruplet = Base64Quadruplet(octets[$ - 4..$]);
        auto triplet = quadruplet.decode;
        sequence ~= triplet.array[0];
        if (quadruplet.array[2].val != '=') {
            sequence ~= triplet.array[1];
        }
        if (quadruplet.array[3].val != '=') {
            sequence ~= triplet.array[2];
        }

        return sequence;
    }

    void toString (W) (ref W output) {
        foreach (o; octets) {
            put(output, o.val);
        }
    }
}

Base64Sequence makeBase64Sequence (Base64Octet[] octets) {
    return Base64Sequence(octets);
}

Base64Sequence makeBase64Sequence (string str) {
    return Base64Sequence(str);
}

unittest {
    {
        string str = "M";
        auto strEncoded = str.encodeSequence;
        assert(cast(string) strEncoded.octets == "TQ==");

        auto strDecoded = strEncoded.decodeSequence;
        assert(cast(string) strDecoded == "M");
    }

    {
        string str = "Ma";
        auto strEncoded = str.encodeSequence;
        assert(cast(string) strEncoded.octets == "TWE=");

        auto strDecoded = strEncoded.decodeSequence;
        assert(cast(string) strDecoded == "Ma");
    }

    {
        string str = "Man";
        auto strEncoded = str.encodeSequence;
        assert(cast(string) strEncoded.octets == "TWFu");

        auto strDecoded = strEncoded.decodeSequence;
        assert(cast(string) strDecoded == "Man");
    }

    {
        string str = "Mann";
        auto strEncoded = str.encodeSequence;
        assert(cast(string) strEncoded.octets == "TWFubg==");

        auto strDecoded = strEncoded.decodeSequence;
        assert(cast(string) strDecoded == "Mann");
    }
}

//--------------------------------------------------------------------------------------------------------------------
