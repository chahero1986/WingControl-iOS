import SwiftUI

struct InfoView: View {
    @EnvironmentObject private var controller: WingController

    private struct LaunchEntry: Identifiable {
        let id: Int
        let date: Date
    }

    private var launchEntries: [LaunchEntry] {
        controller.launchLogs.enumerated().map { LaunchEntry(id: $0.offset, date: $0.element) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("功能说明") {
                    InfoRow(
                        icon: "arrow.up.arrow.down",
                        title: "手动升降",
                        detail: "尾翼共 0 / 3 / 4 / 5 四档。点按档位数字直接设定，「升」「降」逐级调节，一键上升 / 一键下降直接到 5 档或 0 档。"
                    )
                    InfoRow(
                        icon: "speedometer",
                        title: "自动升降模式",
                        detail: "车速降低小于指定码数后触发尾翼下降，车速提高大于指定码数后触发尾翼升起。降速与加速临界范围总大于 20 码；两列同时设为 0 会进入校准模式。"
                    )
                    InfoRow(
                        icon: "flag.checkered",
                        title: "赛道模式",
                        detail: "车辆大幅度降速(加速度 a 由正转为负，当 a 触达设定条件时)将使尾翼进一步升起(持续 5s)，增加持续时间内车体的下压力，进而加强减速时车身抓地力。可设强 / 中 / 弱三档。"
                    )
                    InfoRow(
                        icon: "key.fill",
                        title: "点火升降",
                        detail: "需在车内安装实体按键，设备上报「已就绪」后才可开启或关闭。操作结果以设备回复为准。"
                    )
                }

                Section("蓝牙协议（由原小程序还原）") {
                    Text("指令帧 6 字节：BB | did | 80 | cmd | p1 | p2；did 为 App 首次启动生成的 0~255 随机值并持久化。")
                        .font(.caption)
                    ProtocolRow(name: "设置档位", hex: "BB did 80 01 step 00")
                    ProtocolRow(name: "自动升降", hex: "BB did 80 02 down up")
                    ProtocolRow(name: "关闭自动", hex: "BB did 80 03 00 00")
                    ProtocolRow(name: "赛道灵敏度", hex: "BB did 80 04 1/2/3 00")
                    ProtocolRow(name: "点火升降", hex: "BB did 80 05 0/1 00")
                    ProtocolRow(name: "一键升 / 降", hex: "BB did 80 06 01/02 00")
                    Text("设备通过 notify 上报 8 字节基础帧（auto / 档位 / 车速 / 降速临界 / 升速临界）或 12 字节扩展帧（追加赛道类型 / 点火开关 / 点火就绪 / 点火结果）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("扫描时只接受名称以 JDY 开头的蓝牙模块；连接后自动发现主服务，并优先选择同时支持 write 与 notify 的特征值。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("启动日志") {
                    if controller.launchLogs.isEmpty {
                        Text("暂无记录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(launchEntries) { entry in
                            Text("\(entry.id + 1). \(entry.date, format: .dateTime.year().month().day().hour().minute().second())")
                                .font(.caption.monospaced())
                                .accessibilityLabel("第 \(entry.id + 1) 次启动")
                        }
                    }
                }

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0").foregroundStyle(.secondary)
                    }
                    Text("本 App 由一款已下架的微信小程序逆向还原，界面素材沿用原包资源，通信协议保持一致。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("说明")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct ProtocolRow: View {
    let name: String
    let hex: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text(name)
                .font(.caption)
                .frame(minWidth: 84, alignment: .leading)
            Text(hex)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name)：\(hex)")
    }
}
