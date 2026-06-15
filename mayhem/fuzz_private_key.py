#!/usr/bin/env python3
# Honest successor to the original starkbank/ecdsa-python OSS-Fuzz harness
# (target name "fuzz_private_key" preserved). The original harness only signed
# and verified a round-trip with a freshly generated key, so attacker-controlled
# bytes never reached the DER/PEM/base64 parsers. This version drives the real
# parsing entry points of the library on fuzzer-controlled input:
#   PrivateKey.fromDer / fromPem
#   PublicKey.fromDer / fromPem / fromString / fromCompressed
#   Signature.fromDer / fromBase64
#
# starkbank-ecdsa signals malformed input by raising a bare `Exception(...)`
# (its validation idiom) together with the usual stdlib parse errors. We catch
# exactly those expected failure modes and let anything unexpected propagate as
# a real crash. Note we catch the *exact* `Exception` type (not its subclasses)
# so genuine bugs surfacing as AttributeError/SystemError/etc. still crash.

import sys
import binascii

import atheris
import fuzz_helpers

with atheris.instrument_imports():
    from ellipticcurve import PrivateKey, PublicKey, Signature


# Concrete stdlib errors that malformed key/signature bytes legitimately raise
# inside the parsers (int(x,16), b64decode, .decode(), recursive der.parse, ...).
_EXPECTED = (
    ValueError,
    IndexError,
    KeyError,
    TypeError,
    OverflowError,
    UnicodeDecodeError,
    RecursionError,
    binascii.Error,
)


def _try(fn, *args, **kwargs):
    try:
        fn(*args, **kwargs)
    except _EXPECTED:
        pass
    except Exception as exc:  # noqa: BLE001 - library's own validation idiom
        # The library raises bare Exception(...) for invalid input. Accept ONLY
        # exact-type Exception; any subclass (AttributeError, RuntimeError, ...)
        # is unexpected and must crash.
        if type(exc) is Exception:
            return
        raise


def TestOneInput(data):
    fdp = fuzz_helpers.EnhancedFuzzedDataProvider(data)
    selector = fdp.ConsumeIntInRange(0, 8)

    if selector == 0:
        _try(PrivateKey.fromDer, fdp.ConsumeRemainingBytes())
    elif selector == 1:
        _try(PrivateKey.fromPem, fdp.ConsumeRemainingString())
    elif selector == 2:
        _try(PublicKey.fromDer, fdp.ConsumeRemainingBytes())
    elif selector == 3:
        _try(PublicKey.fromPem, fdp.ConsumeRemainingString())
    elif selector == 4:
        _try(PublicKey.fromString, fdp.ConsumeRemainingString())
    elif selector == 5:
        _try(PublicKey.fromCompressed, fdp.ConsumeRemainingString())
    elif selector == 6:
        recovery = fdp.ConsumeBool()
        _try(Signature.fromDer, fdp.ConsumeRemainingBytes(), recovery)
    elif selector == 7:
        recovery = fdp.ConsumeBool()
        _try(Signature.fromBase64, fdp.ConsumeRemainingString(), recovery)
    else:
        _try(Signature.fromBase64, fdp.ConsumeRemainingString())


def main():
    atheris.Setup(sys.argv, TestOneInput)
    atheris.Fuzz()


if __name__ == "__main__":
    main()
