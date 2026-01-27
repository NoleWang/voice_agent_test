//
//  CountryCodePickerView.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import SwiftUI

// MARK: - Country Code Picker View
struct CountryCodePickerView: View {
    @Binding var selectedCountryCode: CountryCode
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    private let countryCodeManager = CountryCodeManager.shared
    
    var filteredCountryCodes: [CountryCode] {
        if searchText.isEmpty {
            return countryCodeManager.countryCodes
        }
        return countryCodeManager.countryCodes.filter { country in
            country.name.localizedCaseInsensitiveContains(searchText) ||
            country.code.localizedCaseInsensitiveContains(searchText) ||
            country.id.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 搜索框
                SearchBar(text: $searchText, placeholder: "Search country/region")
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                
                // 区号列表
                List {
                    ForEach(filteredCountryCodes) { country in
                        CountryCodeRow(
                            country: country,
                            isSelected: country.id == selectedCountryCode.id
                        ) {
                            selectedCountryCode = country
                            dismiss()
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Select Country Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Country Code Row Component
struct CountryCodeRow: View {
    let country: CountryCode
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // 国旗
                Text(country.flag)
                    .font(.system(size: 32))
                
                // 国家名称和区号
                VStack(alignment: .leading, spacing: 4) {
                    Text(country.name)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Text(country.code)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 选中标记
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Search Bar Component
struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
        )
    }
}

#Preview {
    CountryCodePickerView(selectedCountryCode: .constant(CountryCodeManager.shared.defaultCountryCode))
}

