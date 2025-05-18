//
//  Donation.swift
//  CharityPad
//
//  Created by Wilkes Shluchim on 5/12/25.
//

import Foundation

struct Donation: Identifiable, Codable {
    var id: String
    var amount: Double
    var date: Date
    var transactionId: String?
    
    init(amount: Double, transactionId: String? = nil) {
        self.id = UUID().uuidString
        self.amount = amount
        self.date = Date()
        self.transactionId = transactionId
    }
}
