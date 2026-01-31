//
//  LiveKitBootstrapPayload.swift
//  VoiceAgent
//
//  Created by OpenAI on 1/4/25.
//

import Foundation

struct LiveKitBootstrapPayload: Codable {
    struct Profile: Codable {
        let firstName: String
        let lastName: String
        let email: String
        let address: String
        let phone: String

        enum CodingKeys: String, CodingKey {
            case firstName = "first_name"
            case lastName = "last_name"
            case email
            case address
            case phone
        }
    }

    struct Dispute: Codable {
        let summary: String
        let amount: Double
        let currency: String
        let merchant: String
        let txnDate: String
        let reason: String
        let last4: String
        let fullCardNumber: String?
        let bankName: String?
        let bankPhoneNumber: String?

        enum CodingKeys: String, CodingKey {
            case summary
            case amount
            case currency
            case merchant
            case txnDate = "txn_date"
            case reason
            case last4
            case fullCardNumber
            case bankName
            case bankPhoneNumber
        }
    }

    let profile: Profile
    let dispute: Dispute?
}

extension LiveKitBootstrapPayload.Profile {
    init(userProfile: UserProfile) {
        self.init(
            firstName: userProfile.firstName,
            lastName: userProfile.lastName,
            email: userProfile.email,
            address: userProfile.address,
            phone: userProfile.phoneNumber
        )
    }
}

extension LiveKitBootstrapPayload.Dispute {
    init(dispute: DisputeCase.Dispute) {
        self.init(
            summary: dispute.summary,
            amount: dispute.amount,
            currency: dispute.currency,
            merchant: dispute.merchant,
            txnDate: dispute.txn_date,
            reason: dispute.reason,
            last4: dispute.last4,
            fullCardNumber: dispute.fullCardNumber,
            bankName: dispute.bankName,
            bankPhoneNumber: dispute.bankPhoneNumber
        )
    }
}
