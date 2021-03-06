//
//  RSA.swift
//  JOSESwift
//
//  Created by Carol Capek on 06.02.18.
//
//  ---------------------------------------------------------------------------
//  Copyright 2018 Airside Mobile Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//  ---------------------------------------------------------------------------
//

import Foundation
import Security

internal enum RSAError: Error {
    case algorithmNotSupported
    case signingFailed(description: String)
    case verifyingFailed(description: String)
    case plainTextLengthNotSatisfied
    case cipherTextLenghtNotSatisfied
    case encryptingFailed(description: String)
    case decryptingFailed(description: String)
}

fileprivate extension SignatureAlgorithm {
    var secKeyAlgorithm: SecKeyAlgorithm? {
        switch self {
        case .RS512:
            return .rsaSignatureMessagePKCS1v15SHA512
        }
    }
}

fileprivate extension AsymmetricKeyAlgorithm {
    var secKeyAlgorithm: SecKeyAlgorithm? {
        switch self {
        case .RSA1_5:
            return .rsaEncryptionPKCS1
        }
    }

    /// Checks if the plain text length does not exceed the maximum
    /// for the chosen algorithm and the corresponding public key.
    func isPlainTextLengthSatisfied(_ plainText: Data, for publicKey: SecKey) -> Bool {
        switch self {
        case .RSA1_5:
            // For detailed information about the allowed plain text length for RSAES-PKCS1-v1_5,
            // please refer to the RFC(https://tools.ietf.org/html/rfc3447#section-7.2).
            return plainText.count < (SecKeyGetBlockSize(publicKey) - 11)
        }
    }

    func isCipherTextLenghtSatisfied(_ cipherText: Data, for privateKey: SecKey) -> Bool {
        switch self {
        case .RSA1_5:
            return cipherText.count == SecKeyGetBlockSize(privateKey)
        }
    }
}

internal struct RSA {
    typealias KeyType = SecKey

    ///  Signs input data with a given `RSA` algorithm and the corresponding private key.
    ///
    /// - Parameters:
    ///   - signingInput: The data to sign.
    ///   - privateKey: The private key used by the `SignatureAlgorithm`.
    ///   - algorithm: The algorithm to sign the input data.
    /// - Returns: The signature.
    /// - Throws: `RSAError` if any errors occur while signing the input data.
    static func sign(_ signingInput: Data, with privateKey: KeyType, and algorithm: SignatureAlgorithm) throws -> Data {
        // Check if `SignatureAlgorithm` supports a `SecKeyAlgorithm` and
        // if the algorithm is supported to sign with a given private key.
        guard let algorithm = algorithm.secKeyAlgorithm, SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
            throw RSAError.algorithmNotSupported
        }

        // Sign the input with a given `SecKeyAlgorithm` and a private key.
        var signingError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey, algorithm, signingInput as CFData, &signingError) else {
            throw RSAError.signingFailed(
                description: signingError?.takeRetainedValue().localizedDescription ?? "No description available."
            )
        }

        return signature as Data
    }

    /// Verifies input data against a signature with a given `RSA` algorithm and the corresponding public key.
    ///
    /// - Parameters:
    ///   - verifyingInput: The data to verify.
    ///   - signature: The signature to verify against.
    ///   - publicKey: The public key used by the `SignatureAlgorithm`.
    ///   - algorithm: The algorithm to verify the input data.
    /// - Returns: True if the signature is verified, false if it is not verified.
    /// - Throws: `RSAError` if any errors occur while verifying the input data against the signature.
    static func verify(_ verifyingInput: Data, against signature: Data, with publicKey: KeyType, and algorithm: SignatureAlgorithm) throws -> Bool {
        // Check if `SignatureAlgorithm` supports a `SecKeyAlgorithm` and
        // if the algorithm is supported to verify with a given public key.
        guard
            let algorithm = algorithm.secKeyAlgorithm, SecKeyIsAlgorithmSupported(publicKey, .verify, algorithm)
        else {
            throw RSAError.algorithmNotSupported
        }

        // Verify the signature against an input with a given `SecKeyAlgorithm` and a public key.
        var verificationError: Unmanaged<CFError>?
        guard
            SecKeyVerifySignature(
                publicKey, algorithm, verifyingInput as CFData, signature as CFData, &verificationError
            )
        else {
            if let description = verificationError?.takeRetainedValue().localizedDescription {
                throw RSAError.verifyingFailed(description: description)
            }

            return false
        }

        return true
    }

    /// Encrypts a plain text using a given `RSA` algorithm and the corresponding public key.
    ///
    /// - Parameters:
    ///   - plaintext: The plain text to encrypt.
    ///   - publicKey: The public key.
    ///   - algorithm: The algorithm used to encrypt the plain text.
    /// - Returns: The cipher text (encrypted plain text).
    /// - Throws: `EncryptionError` if any errors occur while encrypting the plain text.
    static func encrypt(_ plaintext: Data, with publicKey: KeyType, and algorithm: AsymmetricKeyAlgorithm) throws -> Data {
        // Check if `AsymmetricKeyAlgorithm` supports a `SecKeyAlgorithm` and
        // if the algorithm is supported to encrypt with a given public key.
        guard
            let secKeyAlgorithm = algorithm.secKeyAlgorithm,
            SecKeyIsAlgorithmSupported(publicKey, .encrypt, secKeyAlgorithm)
        else {
            throw RSAError.algorithmNotSupported
        }

        // Check if the plain text length does not exceed the maximum.
        // e.g. for RSA1_5 the plaintext must be 11 bytes smaller than the public key's modulus.
        guard algorithm.isPlainTextLengthSatisfied(plaintext, for: publicKey) else {
            throw RSAError.plainTextLengthNotSatisfied
        }

        // Encrypt the plain text with a given `SecKeyAlgorithm` and a public key.
        var encryptionError: Unmanaged<CFError>?
        guard
            let cipherText = SecKeyCreateEncryptedData(publicKey, secKeyAlgorithm, plaintext as CFData, &encryptionError)
        else {
            throw RSAError.encryptingFailed(
                description: encryptionError?.takeRetainedValue().localizedDescription ?? "No description available."
            )
        }

        return cipherText as Data
    }

    /// Decrypts a cipher text using a given `RSA` algorithm and the corresponding private key.
    ///
    /// - Parameters:
    ///   - ciphertext: The cipher text to decrypt.
    ///   - privateKey: The private key.
    ///   - algorithm: The algorithm used to decrypt the cipher text.
    /// - Returns: The plain text.
    /// - Throws: `EncryptionError` if any errors occur while decrypting the cipher text.
    static func decrypt(_ ciphertext: Data, with privateKey: KeyType, and algorithm: AsymmetricKeyAlgorithm) throws -> Data {
        // Check if `AsymmetricKeyAlgorithm` supports a `SecKeyAlgorithm` and
        // if the algorithm is supported to decrypt with a given private key.
        guard
            let secKeyAlgorithm = algorithm.secKeyAlgorithm,
            SecKeyIsAlgorithmSupported(privateKey, .decrypt, secKeyAlgorithm)
        else {
            throw RSAError.algorithmNotSupported
        }

        // Check if the cipher text length does not exceed the maximum.
        // e.g. for RSA1_5 the cipher text has the same length as the private key's modulus.
        guard algorithm.isCipherTextLenghtSatisfied(ciphertext, for: privateKey) else {
            throw RSAError.cipherTextLenghtNotSatisfied
        }

        // Decrypt the cipher text with a given `SecKeyAlgorithm` and a private key.
        var decryptionError: Unmanaged<CFError>?
        guard
            let plainText = SecKeyCreateDecryptedData(privateKey, secKeyAlgorithm, ciphertext as CFData, &decryptionError)
        else {
            throw RSAError.decryptingFailed(
                description: decryptionError?.takeRetainedValue().localizedDescription ?? "No description available."
            )
        }

        return plainText as Data
    }
}
