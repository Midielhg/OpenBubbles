import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

/// WebAuthn pieces for iCloud Keychain passkeys (ES256 / P-256), used by the browser extension.
///
/// Keys use Apple's keychain layout: the uncompressed public point (0x04 || X || Y) followed by the
/// private scalar, as rustpush's `Passkey::encode_key` writes them.
class WebAuthn {
  /// Apple's AAGUID for iCloud Keychain, so sites list new passkeys as "iCloud Keychain".
  static final aaguid = _hex("fbfc3007154e4ecc8c0b6e020557d7bd");

  static const _flagUserPresent = 0x01;
  static const _flagUserVerified = 0x04;
  static const _flagBackupEligible = 0x08;
  static const _flagBackedUp = 0x10;
  static const _flagAttestedData = 0x40;

  static final _curve = ECCurve_prime256v1();

  static Uint8List sha256(List<int> data) => Uint8List.fromList(crypto.sha256.convert(data).bytes);

  static String b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll("=", "");

  static Uint8List fromB64url(String value) => base64Url.decode(base64Url.normalize(value));

  static Uint8List _hex(String hex) =>
      Uint8List.fromList([for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);

  static Uint8List _bigIntBytes(BigInt value, int length) {
    final out = Uint8List(length);
    var v = value;
    for (var i = length - 1; i >= 0; i--) {
      out[i] = (v & BigInt.from(0xff)).toInt();
      v = v >> 8;
    }
    return out;
  }

  static BigInt _bytesBigInt(List<int> bytes) =>
      bytes.fold(BigInt.zero, (acc, b) => (acc << 8) | BigInt.from(b));

  // ---------- keys ----------

  /// A new P-256 key in Apple's keychain layout.
  static Uint8List generateKey() {
    final random = FortunaRandom()
      ..seed(KeyParameter(Uint8List.fromList(List.generate(32, (_) => Random.secure().nextInt(256)))));
    final generator = ECKeyGenerator()
      ..init(ParametersWithRandom(ECKeyGeneratorParameters(_curve), random));
    final pair = generator.generateKeyPair();
    final public = pair.publicKey as ECPublicKey;
    final private = pair.privateKey as ECPrivateKey;
    return Uint8List.fromList([...public.Q!.getEncoded(false), ..._bigIntBytes(private.d!, 32)]);
  }

  /// The uncompressed public point (65 bytes) of a key in Apple's layout.
  static Uint8List publicPoint(Uint8List appleKey) => Uint8List.sublistView(appleKey, 0, 65);

  /// SubjectPublicKeyInfo (DER) for a P-256 public point, as `getPublicKey()` returns it.
  static Uint8List spki(Uint8List point) =>
      Uint8List.fromList([..._hex("3059301306072a8648ce3d020106082a8648ce3d030107034200"), ...point]);

  /// COSE_Key for the public key (kty EC2, alg ES256, crv P-256).
  static Uint8List coseKey(Uint8List point) => Uint8List.fromList(cbor.encode(CborMap({
        CborSmallInt(1): CborSmallInt(2),
        CborSmallInt(3): CborSmallInt(-7),
        CborSmallInt(-1): CborSmallInt(1),
        CborSmallInt(-2): CborBytes(point.sublist(1, 33)),
        CborSmallInt(-3): CborBytes(point.sublist(33, 65)),
      })));

  /// ECDSA P-256 / SHA-256 signature (DER), deterministic (RFC 6979).
  static Uint8List sign(Uint8List appleKey, List<int> message) {
    final d = _bytesBigInt(appleKey.sublist(65));
    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter(ECPrivateKey(d, _curve)));
    final sig = signer.generateSignature(Uint8List.fromList(message)) as ECSignature;
    return _derSignature(sig.r, sig.s);
  }

  static Uint8List _derInt(BigInt value) {
    var bytes = _bigIntBytes(value, 32).toList();
    while (bytes.length > 1 && bytes[0] == 0 && bytes[1] < 0x80) {
      bytes = bytes.sublist(1);
    }
    if (bytes[0] >= 0x80) bytes = [0, ...bytes];
    return Uint8List.fromList([0x02, bytes.length, ...bytes]);
  }

  static Uint8List _derSignature(BigInt r, BigInt s) {
    final body = [..._derInt(r), ..._derInt(s)];
    return Uint8List.fromList([0x30, body.length, ...body]);
  }

  // ---------- user tag (Apple's "atag": CBOR with the site's user id and names) ----------

  static Uint8List userTag({required Uint8List id, String? name, String? displayName}) =>
      Uint8List.fromList(cbor.encode(CborMap({
        CborString("id"): CborBytes(id),
        if (name != null) CborString("name"): CborString(name),
        if (displayName != null) CborString("displayName"): CborString(displayName),
      })));

  static ({Uint8List? id, String? name, String? displayName}) readUserTag(Uint8List tag) {
    try {
      final map = cbor.decode(tag);
      if (map is! CborMap) return (id: null, name: null, displayName: null);
      Object? field(String key) => map[CborString(key)];
      final id = field("id");
      final name = field("name");
      final displayName = field("displayName");
      return (
        id: id is CborBytes ? Uint8List.fromList(id.bytes) : null,
        name: name is CborString ? name.toString() : null,
        displayName: displayName is CborString ? displayName.toString() : null,
      );
    } catch (_) {
      return (id: null, name: null, displayName: null);
    }
  }

  // ---------- ceremonies ----------

  static Uint8List _authData(String rpId, int flags, [List<int> attested = const []]) =>
      Uint8List.fromList([...sha256(utf8.encode(rpId)), flags, 0, 0, 0, 0, ...attested]);

  static int _flags({required bool userVerified, bool attested = false}) =>
      _flagUserPresent |
      (userVerified ? _flagUserVerified : 0) |
      _flagBackupEligible |
      _flagBackedUp |
      (attested ? _flagAttestedData : 0);

  /// navigator.credentials.get(): authenticatorData and signature over it plus the client data hash.
  static ({Uint8List authenticatorData, Uint8List signature}) assert_({
    required String rpId,
    required Uint8List appleKey,
    required Uint8List clientDataHash,
    required bool userVerified,
  }) {
    final authenticatorData = _authData(rpId, _flags(userVerified: userVerified));
    final signature = sign(appleKey, [...authenticatorData, ...clientDataHash]);
    return (authenticatorData: authenticatorData, signature: signature);
  }

  /// navigator.credentials.create(): authenticatorData with the new credential, and a "none"
  /// attestation object around it.
  static ({Uint8List authenticatorData, Uint8List attestationObject}) register({
    required String rpId,
    required Uint8List appleKey,
    required Uint8List credentialId,
    required bool userVerified,
  }) {
    final point = publicPoint(appleKey);
    final attested = [
      ...aaguid,
      (credentialId.length >> 8) & 0xff,
      credentialId.length & 0xff,
      ...credentialId,
      ...coseKey(point),
    ];
    final authenticatorData = _authData(rpId, _flags(userVerified: userVerified, attested: true), attested);
    final attestationObject = Uint8List.fromList(cbor.encode(CborMap({
      CborString("fmt"): CborString("none"),
      CborString("attStmt"): CborMap({}),
      CborString("authData"): CborBytes(authenticatorData),
    })));
    return (authenticatorData: authenticatorData, attestationObject: attestationObject);
  }

  static Uint8List randomBytes(int length) =>
      Uint8List.fromList(List.generate(length, (_) => Random.secure().nextInt(256)));
}
