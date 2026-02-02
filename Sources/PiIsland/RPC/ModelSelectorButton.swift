
//
//  ModelSelectorButton.swift
//  PiIsland
//
//  Created by Pi Agent on 2024-05-15.
//

import SwiftUI

struct ModelSelectorButton: View {
    @Bindable var session: ManagedSession
    
    var body: some View {
        Menu {
            ForEach(sortedProviders, id: \.self) { provider in
                Section(provider) {
                    ForEach(modelsForProvider(provider)) { model in
                        Button(action: { selectModel(model) }) {
                            HStack {
                                Text(model.displayName)
                                if isCurrentModel(model) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 2) { // Match Back Button spacing
                Text(session.model?.displayName ?? "Select Model")
                    .font(.system(size: 11, weight: .medium)) // Match Back Button font
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 100)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .padding(.horizontal, 6)
        .padding(.vertical, 4) // Restore standard padding
        .background(Color.white.opacity(0.08))
        .clipShape(.rect(cornerRadius: 6))
    }
    
    private var sortedProviders: [String] {
        session.modelsByProvider.keys.sorted()
    }
    
    private func modelsForProvider(_ provider: String) -> [RPCModel] {
        session.modelsByProvider[provider] ?? []
    }
    
    private func isCurrentModel(_ model: RPCModel) -> Bool {
        guard let current = session.model else { return false }
        return current.id == model.id && current.provider == model.provider
    }
    
    private func selectModel(_ model: RPCModel) {
        Task {
            await session.setModel(provider: model.provider, modelId: model.id)
        }
    }
}
