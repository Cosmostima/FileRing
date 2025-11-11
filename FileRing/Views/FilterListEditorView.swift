//
//  FilterListEditorView.swift
//  FileRing
//
//  List editor for managing excluded folders and extensions
//

import SwiftUI

struct FilterListEditorView: View {
    let title: String
    let placeholder: String
    let itemPrefix: String // e.g., "" for folders, "." for extensions
    @Binding var items: [String]
    @Environment(\.dismiss) private var dismiss

    @State private var newItem: String = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var selectedItem: String?
    @State private var showAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()

            Divider()

            // Content area with table
            VStack(spacing: 16) {
                // Table-like list
                VStack(spacing: 0) {
                    // Table header
                    HStack {
                        Text("Name")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    // Table content
                    if items.isEmpty {
                        VStack {
                            Spacer()
                            Text("No items yet")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text("Add items using the buttons below")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(items, id: \.self) { item in
                                    HStack {
                                        Text(item)
                                            .font(.system(.body, design: .monospaced))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(selectedItem == item ? Color.accentColor : Color.clear)
                                    .foregroundStyle(selectedItem == item ? .white : .primary)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedItem = item
                                    }

                                    if item != items.last {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )

                // Action buttons
                HStack(spacing: 12) {
                    Button("Add") {
                        showAddDialog()
                    }
                    .buttonStyle(.bordered)

                    Button("Delete") {
                        if let selected = selectedItem {
                            removeItem(selected)
                            selectedItem = nil
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedItem == nil)

                    Spacer()

                    Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 520, height: 450)
        .alert("Invalid Item", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .sheet(isPresented: $showAddSheet) {
            AddItemDialog(
                placeholder: placeholder,
                itemPrefix: itemPrefix,
                onAdd: { item in
                    addItemDirectly(item)
                }
            )
        }
    }

    private func showAddDialog() {
        showAddSheet = true
    }

    private func addItemDirectly(_ item: String) {
        var trimmed = item.trimmingCharacters(in: .whitespaces)

        // Validate not empty
        guard !trimmed.isEmpty else { return }

        // Add prefix if needed (for extensions)
        if !itemPrefix.isEmpty && !trimmed.hasPrefix(itemPrefix) {
            trimmed = itemPrefix + trimmed
        }

        // Check for duplicates
        if items.contains(trimmed) {
            alertMessage = "'\(trimmed)' already exists in the list"
            showAlert = true
            return
        }

        // Add to list
        items.append(trimmed)
    }

    private func removeItem(_ item: String) {
        items.removeAll { $0 == item }
    }
}

// MARK: - Add Item Dialog
struct AddItemDialog: View {
    let placeholder: String
    let itemPrefix: String
    let onAdd: (String) -> Void

    @State private var inputText: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Add New Item")
                .font(.headline)

            TextField(placeholder, text: $inputText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    addAndClose()
                }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Add") {
                    addAndClose()
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }

    private func addAndClose() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onAdd(trimmed)
        dismiss()
    }
}
