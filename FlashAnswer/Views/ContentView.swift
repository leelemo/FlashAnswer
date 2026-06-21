import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var vm = MainViewModel()
    @State private var showFilePicker = false
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Status card
                statusCard

                Spacer()

                // Question bank info + clear button
                if !vm.bank.questions.isEmpty {
                    HStack {
                        Text("题库：\(vm.bank.questions.count) 道题")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Label("清空题库", systemImage: "trash")
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal)
                }

                // Action buttons
                HStack(spacing: 16) {
                    // Import button
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("导入题库", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)

                    // Listen button
                    Button {
                        if !vm.permissionsGranted {
                            vm.requestPermissions()
                        } else {
                            vm.toggleListening()
                        }
                    } label: {
                        Label(vm.isListening ? "停止监听" : "开始监听",
                              systemImage: vm.isListening ? "mic.slash.fill" : "mic.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(vm.isListening ? .red : .green)
                }
                .padding(.horizontal)

                // Restart button (visible after result)
                if vm.isListening {
                    Button("立即重新监听") { vm.restartNow() }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 32)
            .navigationTitle("FlashAnswer")
            .navigationBarTitleDisplayMode(.large)
            .fileImporter(isPresented: $showFilePicker,
                          allowedContentTypes: [.init(filenameExtension: "xlsx")!],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { vm.importExcel(url: url) }
                case .failure(let err):
                    vm.state = .error(err.localizedDescription)
                }
            }
            .alert("清空题库", isPresented: $showClearConfirm) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) { vm.clearBank() }
            } message: {
                Text("确定要清空所有题库吗？此操作不可撤销。")
            }
            .onAppear { vm.requestPermissions() }
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        VStack(spacing: 12) {
            switch vm.state {
            case .idle:
                if vm.isListening {
                    Image(systemName: "waveform")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                        .symbolEffect(.variableColor.iterative)
                    Text("监听中...")
                        .font(.headline)
                } else {
                    Image(systemName: "ear")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("点击开始监听")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

            case .listening:
                Image(systemName: "waveform")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                    .symbolEffect(.variableColor.iterative)
                Text("监听中...")
                    .font(.headline)

            case .matched(let results):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("匹配到 \(results.count) 道题")
                    .font(.headline)
                ForEach(Array(results.prefix(3).enumerated()), id: \.offset) { _, result in
                    VStack(spacing: 4) {
                        Text("【\(result.question.type)】答案：\(result.question.answer)")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                        Text(result.question.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .padding(.top, 4)
                }
                if results.count > 3 {
                    Text("还有 \(results.count - 3) 道题，查看通知栏")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

            case .noMatch(let text):
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text("未匹配到题目")
                    .font(.headline)
                Text("识别到：\(text)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

            case .error(let msg):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                Text(msg)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

#Preview {
    ContentView()
}
