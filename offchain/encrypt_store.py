"""
Off-chain helper for the Medical Records project.

  encrypt <file>          -> AES (Fernet) encrypt, save to storage/, print hash + content id
  verify  <content-id>    -> recompute SHA-256 of the stored file and compare to a hash
  decrypt <content-id> <key-file> -> restore the original file

The printed 0x... hash goes into MedicalRecords.addRecord(cid, dataHash).
Storage is a local folder that stands in for IPFS. To use real IPFS later,
upload storage/<id>.enc (e.g. via Pinata) and use the returned CID as `cid`.

Setup:  pip install cryptography
"""
import hashlib
import sys
from pathlib import Path

from cryptography.fernet import Fernet

STORAGE = Path(__file__).parent / "storage"


def sha256_hex(data: bytes) -> str:
    return "0x" + hashlib.sha256(data).hexdigest()


def encrypt(path: str) -> None:
    STORAGE.mkdir(exist_ok=True)
    plain = Path(path).read_bytes()
    key = Fernet.generate_key()
    blob = Fernet(key).encrypt(plain)
    digest = sha256_hex(blob)
    content_id = "local-" + digest[2:18]
    (STORAGE / f"{content_id}.enc").write_bytes(blob)
    key_file = STORAGE / f"{content_id}.key"
    key_file.write_bytes(key)
    print("content id :", content_id)
    print("data hash  :", digest, "(SHA-256 of the encrypted file)")
    print("key file   :", key_file, "(patient keeps this; share only with authorized doctors)")


def verify(content_id: str, expected_hash: str) -> None:
    blob = (STORAGE / f"{content_id}.enc").read_bytes()
    actual = sha256_hex(blob)
    print("actual  :", actual)
    print("expected:", expected_hash)
    print("MATCH" if actual == expected_hash.lower() else "TAMPERED / MISMATCH")


def decrypt(content_id: str, key_file: str) -> None:
    blob = (STORAGE / f"{content_id}.enc").read_bytes()
    plain = Fernet(Path(key_file).read_bytes()).decrypt(blob)
    out = STORAGE / f"{content_id}.decrypted"
    out.write_bytes(plain)
    print("written:", out)


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "encrypt":
        encrypt(sys.argv[2])
    elif len(sys.argv) >= 4 and sys.argv[1] == "verify":
        verify(sys.argv[2], sys.argv[3])
    elif len(sys.argv) >= 4 and sys.argv[1] == "decrypt":
        decrypt(sys.argv[2], sys.argv[3])
    else:
        print(__doc__)
