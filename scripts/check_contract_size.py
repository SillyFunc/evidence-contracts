"""Check the compiled registry against FISCO BCOS 2.x's 256 KiB limit.

Run after `forge build`. Forge's --sizes command applies Ethereum's EIP-170
limit even when code_size_limit is configured for the FISCO test environment.
"""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ARTIFACT = ROOT / "out" / "CarbonEvidenceRegistry.sol" / "CarbonEvidenceRegistry.json"
MAX_RUNTIME_BYTES = 256 * 1024


def bytecode_size(value: str) -> int:
    value = value.removeprefix("0x")
    # Also rejects unresolved library links or malformed compilation output.
    return len(bytes.fromhex(value))


def main() -> None:
    if not ARTIFACT.is_file():
        raise SystemExit("Missing compilation artifact; run forge build first.")
    artifact = json.loads(ARTIFACT.read_text(encoding="utf-8"))
    runtime_size = bytecode_size(artifact["deployedBytecode"]["object"])
    init_size = bytecode_size(artifact["bytecode"]["object"])
    if not runtime_size:
        raise SystemExit("Registry runtime bytecode is empty.")
    print(f"CarbonEvidenceRegistry runtime: {runtime_size:,} bytes")
    print(f"Initialization bytecode: {init_size:,} bytes")
    print(f"FISCO BCOS 2.x runtime limit: {MAX_RUNTIME_BYTES:,} bytes")
    if runtime_size > MAX_RUNTIME_BYTES:
        raise SystemExit("Registry exceeds the FISCO BCOS 2.x code size limit.")
    print("Code size check passed. Target-node deployment still requires verification.")


if __name__ == "__main__":
    main()
