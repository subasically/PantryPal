import SwiftUI

struct InventoryItemRow: View {
    let item: InventoryItem
    @Binding var viewModel: InventoryViewModel
    var onEdit: () -> Void = {}
    var onRemove: (InventoryItem) async -> Void // Handler for full removal
    var onDecrement: (InventoryItem) async -> Void // Handler for decrement (may trigger grocery logic)
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 12) {
                // Product image placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "shippingbox")
                        .foregroundColor(.gray)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName)
                        .font(.headline)
                        .lineLimit(1)
                        .accessibilityIdentifier(item.displayName)
                    
                    if let brand = item.productBrand {
                        Text(brand)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    
                    if let locationName = item.locationName {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.caption2)
                            Text(locationName)
                                .font(.caption)
                        }
                        .foregroundStyle(.tertiary)
                    }
                    
                    if let expDate = item.expirationDate {
                        HStack(spacing: 4) {
                            Image(systemName: item.isExpired ? "exclamationmark.triangle.fill" : (item.isExpiringSoon ? "clock.fill" : "calendar"))
                                .font(.caption2)
                            Text(formatDate(expDate))
                                .font(.caption)
                        }
                        .foregroundColor(item.isExpired ? .ppDanger : (item.isExpiringSoon ? .ppOrange : .ppSecondaryText))
                    }
                }
                
                Spacer()
                
                // Quantity controls
                HStack(spacing: 8) {
                    Button(action: {
                        if item.quantity <= 1 {
                            showDeleteConfirmation = true
                            HapticService.shared.warning()
                        } else {
                            HapticService.shared.lightImpact()
                            Task { await onDecrement(item) }
                        }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(Color(uiColor: .systemGray4))
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("inventory.decrement.\(item.id)")
                    
                    Text("\(item.quantity)")
                        .font(.headline)
                        .foregroundColor(.ppPurple)
                        .frame(minWidth: 30)
                        .accessibilityIdentifier("inventory.quantity.\(item.id)")
                    
                    Button(action: {
                        HapticService.shared.lightImpact()
                        Task {
                            await viewModel.adjustQuantity(id: item.id, adjustment: 1)
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.ppGreen)
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("inventory.increment.\(item.id)")
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary)
        .padding(.vertical, 4)
        .alert("Remove Item?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                Task {
                    await onRemove(item)
                }
            }
        } message: {
            Text("This will remove \"\(item.displayName)\" from your pantry.")
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
