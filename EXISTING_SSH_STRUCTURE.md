# EXISTING_SSH_STRUCTURE

## 1. Legacy Oracle

- Root (workspace-relative): `legacy_openssh_code/openssh-portable`
- Upstream: `https://github.com/openssh/openssh-portable`
- Role: behavioral oracle for handshake sequences, auth flows, channel behavior, error responses, and wire format parity.

### 1.1 Local Checkout Policy

The OpenSSH oracle checkout is a **local, gitignored workspace dependency** and is
not required to be committed into this repository.

If the path is missing on a fresh clone, provision it locally:

```bash
mkdir -p legacy_openssh_code
git clone https://github.com/openssh/openssh-portable legacy_openssh_code/openssh-portable
```

Conformance preflight MUST assert this path exists locally before harness runs.

## 2. Subsystem Map

| Subsystem | Legacy Paths | Parity Critical Notes |
|---|---|---|
| Transport / packets | `packet.c`, `dispatch.c` | Binary packet framing, sequence numbers, padding, encryption/MAC application order |
| Key exchange | `kex.c`, `kexgen.c`, `kexdh.c`, `kexecdh.c`, `kexsntrup761x25519.c` | Algorithm negotiation order, strict KEX mode, exchange hash computation |
| Ciphers / MAC | `cipher.c`, `cipher-chachapoly.c`, `cipher-aesctr.c`, `mac.c`, `umac.c` | AEAD vs encrypt-then-MAC, key derivation from shared secret |
| Authentication | `auth.c`, `auth2.c`, `auth2-pubkey.c`, `auth2-passwd.c`, `auth2-kbdint.c` | Method ordering, partial success, max attempts, banner, timeout |
| Key types | `sshkey.c`, `ssh-ed25519.c`, `ssh-rsa.c`, `ssh-ecdsa.c` | Key parsing, signing, verification, certificate extensions |
| Channels | `channels.c` | Multiplexing, window management, flow control, channel types |
| Session | `session.c`, `serverloop.c` | PTY allocation, exec, env, signals, exit status, subsystem dispatch |
| SFTP | `sftp-server.c`, `sftp-client.c`, `sftp-common.c` | Request-response correlation, file handle lifecycle, v3 semantics |
| Agent | `ssh-agent.c`, `authfd.c` | Key listing, signing, add/remove, constraints |
| Config | `readconf.c`, `servconf.c` | Client/server configuration directives |
| Buffers | `sshbuf.c`, `sshbuf-getput-basic.c`, `sshbuf-getput-crypto.c` | Secure buffer read/write helpers, mpint encoding |

## 3. Semantics To Preserve Exactly (V1)

1. SSH-2 binary packet format (RFC 4253 §6) — framing, padding, sequence numbers.
2. Algorithm negotiation order (client preference wins).
3. Key exchange: exchange hash computation, key derivation (RFC 4253 §7.2).
4. Authentication: method ordering, partial success, pubkey two-phase flow.
5. Channel: window management, close sequence (EOF -> close -> response).
6. SFTP: request-ID correlation, status codes, v3 operation semantics.
7. Error responses: disconnect reason codes, error message strings.

## 4. Full Behavioral Extraction

See `FRANKENSSH_PROPOSAL.md` Part VI (Sections 21-27) for complete behavioral
extraction including packet formats, KEX sequences, auth protocol, channel
multiplexing, SFTP operations, and agent protocol.
