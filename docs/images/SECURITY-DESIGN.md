# Security design

This document explains what this project protects, what each control actually stops, and what it doesn't. For setup see [SETUP.md](SETUP.md). For what went wrong while building it see [LESSONS.md](LESSONS.md).

## What are we protecting?

I'm protecting the **privacy** of sensor data sent through the network, and verifying the **authenticity** of the devices.

## Threat model

Without mTLS and strong authentication, if someone has access to our local network, they can sniff the sensor readings from the clients, or modify the readings using a MITM (man-in-the-middle) attack.

| Threat | Mitigated? | How |
|---|---|---|
| Network sniffing (reading the data) | Yes | TLS encryption |
| MITM / impersonation (pretending to be the broker or a device) | Yes | Mutual certificate verification |
| Stolen or lost device credential | No | No revocation yet |
| A valid device publishing to a topic it shouldn't | No | No per-device ACLs |
| CA key theft | No | No passphrase on `ca.key` |
| Physical access to a device's flash | No | No secure boot / flash encryption |

## How this is mitigated

Using mTLS, the data transfer is encrypted, which stops sniffing. I confirmed this myself with a Wireshark capture on port 8883: the TLS handshake shows the certificate exchange, and everything after that is unreadable `Application Data`, no plaintext at any point.

Certificate verification stops MITM, because both the broker and the client check the other side's certificate against the CA before any data is exchanged. I tested this directly: connecting with no client certificate, or one signed by a different CA, gets refused by the broker every time.

## Trust model

I built my own Certificate Authority (CA) for this project, instead of using a public CA, because this is a closed system with no public users, I need full control over who's allowed to connect, not a certificate anyone on the internet could get. The CA's private key (`ca.key`) stays on my PC and is never copied to the broker or any device. The CA signs two kinds of certificates: one for the broker, one for each client device. Every device trusts only this CA, so a certificate it didn't sign is rejected automatically, by both sides.

## A note on allow_anonymous

MQTT allows anonymous connections by default, and my `mosquitto.conf` has `allow_anonymous` set to `true`. That looks unsafe at first, but it isn't a gap: `require_certificate true` means a client must already present a valid certificate signed by my CA before the TLS handshake even completes. No one reaches the MQTT layer, where `allow_anonymous` would matter, without passing that check first. The authentication comes from the TLS layer, not MQTT's own username/password system.

## Known limitations

- **No revocation.** A lost or stolen certificate stays valid until it expires.
- **No per-device ACLs.** Any valid client can publish or subscribe to any topic.
- **The CA private key has no passphrase.**
- **Server and client keys are stored at 644 permissions**, readable by anyone with filesystem access.
- **No secure boot or flash encryption on the ESP32.** The key sits unencrypted in flash.
- **Time is unauthenticated.** The ESP32 trusts NTP without verification.
- **No monitoring.** Nothing logs a refused connection attempt right now.











