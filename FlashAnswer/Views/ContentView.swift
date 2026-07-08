import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var vm = MainViewModel()
    @State private var showFilePicker = false
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // 模式选择
                modePicker

                // 语音模式：题型选择
                if vm.mode == .voice {
                    typePicker
                }

                // 录屏模式：使用说明
                if vm.mode == .screen {
                    screenHelpCard
                    extensionStatusCard
                }

                Divider()

                // 状态卡片
                statusCard

                Spacer()

                // 题库信息
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

                // 操作按钮
                actionButtons

                Text("版本 \(vm.appVersion)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 24)
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
            .onAppear {
                vm.requestPermissions()
                vm.startStatusPolling()
            }
            .onDisappear {
                vm.stopStatusPolling()
            }
        }
    }

    // MARK: - 模式选择
    @ViewBuilder
    private var modePicker: some View {
        Picker("识别模式", selection: $vm.mode) {
            ForEach(RecognitionMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    // MARK: - 题型选择（语音模式）
    @ViewBuilder
    private var typePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MainViewModel.typeKeywords.map(\.display), id: \.self) { type in
                    Button(type) {
                        vm.currentType = type
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(vm.currentType == type ? Color.blue : Color(.systemGray5))
                    .foregroundStyle(vm.currentType == type ? .white : .primary)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - 录屏模式使用说明
    @ViewBuilder
    private var screenHelpCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "display.and.arrow.down")
                .font(.system(size: 36))
                .foregroundStyle(.blue)

            Text("录屏识别模式")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Label("从控制中心启动屏幕录制", systemImage: "1.circle")
                    .font(.caption)
                Label("长按录屏按钮，选择 FlashAnswer", systemImage: "2.circle")
                    .font(.caption)
                Label("开始录屏，系统自动识别题目", systemImage: "3.circle")
                    .font(.caption)
                Label("匹配结果以通知形式推送", systemImage: "4.circle")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 录屏扩展状态

    @ViewBuilder
    private var extensionStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("录屏扩展状态", systemImage: "waveform.badge.magnifyingglass")
                .font(.headline)
            Text(vm.extensionStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 操作按钮
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 16) {
            // 导入按钮
            Button {
                showFilePicker = true
            } label: {
                Label("导入题库", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .tint(.blue)

            // 语音模式：开始/停止监听
            if vm.mode == .voice {
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
        }
        .padding(.horizontal)
    }

    // MARK: - 状态卡片
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
                    Image(systemName: vm.mode == .voice ? "ear" : "display.and.arrow.down")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(vm.mode == .voice ? "点击开始监听" : "按上方说明启动录屏")
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
