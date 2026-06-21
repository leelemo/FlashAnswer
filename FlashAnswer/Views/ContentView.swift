import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var vm = MainViewModel()
    @State private var showFilePicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Status card
                statusCard

                Spacer()

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

                // Question bank info
                if !vm.bank.questions.isEmpty {
                    Text("题库共 \(vm.bank.questions.count) 道题")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Restart button (visible after result)
                if vm.isListening {
                    Button("立即重听") { vm.restartNow() }
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
                    Text("正在聆听...")
                        .font(.headline)
                } else {
                    Image(systemName: "ear")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("点击开始监听")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

            case .matched(let question, let score):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("匹配成功（置信度 \(Int(score * 100))%）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(question.text)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                if !question.options.isEmpty {
                    Text(question.options)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Text("答案：\(question.answer)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)

            case .noMatch(let text):
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text("未找到匹配题目")
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
