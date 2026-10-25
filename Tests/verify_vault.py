"""Independent, synthetic-only Curios v1 interoperability regression.

Uses Python cryptography/OpenSSL, not Curios or CryptoKit, to authenticate a
Swift-produced envelope through both passphrase and recovery routes. No real
vaults/credentials should be supplied to this test helper.
"""
import base64
import hashlib
import hmac
import json
from pathlib import Path
import struct
import sys

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

request = json.load(sys.stdin)
path = Path(request["path"])
assert path.name == "synthetic.curiosvault" and path.parent.name.startswith("interop-")
assert path.stat().st_size <= 64 * 1024 * 1024 + 65536
raw = path.read_bytes()
assert raw[:8] == b"CURIOSV1"
header_size, box_size = struct.unpack(">II", raw[8:16])
assert 0 < header_size <= 16384 and 28 <= box_size <= 64 * 1024 * 1024 + 28
assert len(raw) == 16 + header_size + box_size
end = 16 + header_size
header = json.loads(raw[16:end])
assert header["version"] == 1 and header["cipher"] == "AES-256-GCM"
assert header["kind"] == "export"


def decode(value):
    return base64.b64decode(value, validate=True)


def derive(key, salt, purpose):
    return HKDF(algorithm=hashes.SHA256(), length=32, salt=salt, info=purpose).derive(key)


def decrypt(box, key, aad):
    assert len(box) >= 28
    return AESGCM(key).decrypt(box[:12], box[12:], aad)


recovery = request["recovery"].replace("-", "").upper()
assert recovery.startswith("CURIOS1") and len(recovery) == 79
recovery_bytes = bytes.fromhex(recovery[7:])
secret = recovery_bytes[:32]
assert hmac.compare_digest(hashlib.sha256(secret).digest()[:4], recovery_bytes[32:])

for route in ("passphrase", "recovery"):
    slot = header[route]
    salt = decode(slot["salt"])
    assert len(salt) == 16
    if route == "passphrase":
        assert 600000 <= slot["iterations"] <= 2000000
        key = hashlib.pbkdf2_hmac("sha256", request["passphrase"].encode(), salt, slot["iterations"], 32)
    else:
        assert slot["iterations"] == 0
        key = derive(secret, salt, b"Curios recovery wrapping key v1")
    context = {
        "purpose": "Curios VMK wrapper v1", "vaultID": header["vaultID"],
        "generation": header["generation"], "route": route,
        "salt": slot["salt"], "iterations": slot["iterations"],
    }
    context_bytes = json.dumps(context, sort_keys=True, separators=(",", ":")).encode()
    master = decrypt(decode(slot["wrappedKey"]), key, context_bytes)
    assert len(master) == 32
    content_key = derive(master, header["vaultID"].encode(), b"Curios content key v1")
    plaintext = decrypt(raw[end:], content_key, raw[:end])
    assert hmac.compare_digest(hashlib.sha256(plaintext).hexdigest(), request["sha256"])
    assert json.loads(plaintext)["schemaVersion"] == 1
    bad = bytearray(raw[end:])
    bad[-1] ^= 1
    try:
        decrypt(bytes(bad), content_key, raw[:end])
    except InvalidTag:
        pass
    else:
        raise AssertionError("Tampering was not rejected")
    print(f"PASS independent Python/OpenSSL {route} unwrap, payload authentication and tamper rejection")
