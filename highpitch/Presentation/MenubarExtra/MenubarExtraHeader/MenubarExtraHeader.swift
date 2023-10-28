//
//  ExtraMenubarHeader.swift
//  highpitch
//
//  Created by yuncoffee on 10/19/23.
//

import SwiftUI
import SwiftData
import HotKey

struct MenubarExtraHeader: View {
    @Environment(\.openSettings)
    private var openSettings
    @Environment(\.openWindow)
    private var openWindow
    @Environment(AppleScriptManager.self)
    private var appleScriptManager
    @Environment(ProjectManager.self)
    private var projectManager
    @Environment(KeynoteManager.self)
    private var keynoteManager
    @Environment(MediaManager.self)
    private var mediaManager
    @Environment(\.modelContext)
    var modelContext
    @Binding
    var selectedProject: ProjectModel?
    @Binding
    var selectedKeynote: OpendKeynote?
    @Binding
    var isMenuPresented: Bool
    @Binding
    var isRecording: Bool
    var practiceManager = PracticeManager()
    
    // HotKeys
    let hotkeyStart = HotKey(key: .f5, modifiers: [.command, .control])
    let hotkeyPause = HotKey(key: .space, modifiers: [.command, .control])
    let hotkeySave = HotKey(key: .escape, modifiers: [.command, .control])
    
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: .HPSpacing.xsmall) {
                Button {
                    print("앱 열기")
                    openSelectedProject()
                } label: {
                    Label("홈", systemImage: "house.fill")
                        .systemFont(.caption)
                        .foregroundStyle(Color.HPGray.system800)
                        .labelStyle(.iconOnly)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                Button {
                    print("설정창 열기...")
                    try? openSettings()
                } label: {
                    Label("설정창 열기", systemImage: "gearshape.fill")
                        .systemFont(.caption)
                        .foregroundStyle(Color.HPGray.system800)
                        .labelStyle(.iconOnly)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            HStack(spacing: .HPSpacing.xsmall) {
                let labels = if !mediaManager.isRecording {
                    (
                        label:"연습 시작",
                        image: "play.fill",
                        color: Color.HPPrimary.dark
                    )
                } else {
                    (
                        label:"일시 정지",
                        image: "pause.fill",
                        color: Color.HPGray.system800
                    )
                }
                Button {
                    if !mediaManager.isRecording {
                        playPractice()
                    } else {
                        pausePractice()
                    }
                } label: {
                    Label(labels.label, systemImage: labels.image)
                        .systemFont(.caption2)
                        .foregroundStyle(labels.color)
                        .labelStyle(VerticalIconWithTextLabelStyle())
                        .frame(height: 24)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(!mediaManager.isRecording ? "a" : .space, modifiers: [.command, .option] )
                Button {
                    stopPractice()
                } label: {
                    Label("끝내기", systemImage: "stop.fill")
                        .systemFont(.caption2)
                        .foregroundStyle(Color.HPSecondary.base)
                        .labelStyle(VerticalIconWithTextLabelStyle())
                        .frame(height: 24)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [.command, .option] )
                .disabled(!mediaManager.isRecording)
            }
        }
        .padding(.horizontal, .HPSpacing.xsmall + .HPSpacing.xxxxsmall)
        .frame(minHeight: 48, maxHeight: 48)
        .border(.HPComponent.stroke, width: 1, edges: [.bottom])
        .onAppear {
            // onAppear를 통해서 hotKey들의 동작 함수들을 등록해준다.
            hotkeyStart.keyDownHandler = playPractice
            hotkeyPause.keyDownHandler = pausePractice
            hotkeySave.keyDownHandler = {
                Task {
                    await MainActor.run {
                        stopPractice()
                    }
                }
            }
        }
    }
}

extension MenubarExtraHeader {
    // MARK: - 연습 시작.
    private func playPractice() {
        print("------연습이 시작되었습니다.-------")
        /// 선택된 키노트가 있을 때
        if let selectedKeynote = selectedKeynote {
            Task {
                await appleScriptManager.runScript(.startPresentation(fileName: selectedKeynote.path))
            }
        } else {
            /// 선택된 키노트가 없을 때
        }
        projectManager.temp = selectedProject?.persistentModelID
        keynoteManager.temp = selectedKeynote
        mediaManager.fileName = Date().makeM4aFileName()
        mediaManager.startRecording()
    }
    
    // MARK: - 연습 일시중지
    private func pausePractice() {
        
    }
    
    // MARK: - 연습 끝내기
    @MainActor
    private func stopPractice() {
        if !mediaManager.isRecording {
            return
        }
        print("녹음 종료")
        mediaManager.stopRecording()
        /// mediaManager.fileName에 음성 파일이 저장되어있을거다!!
        /// 녹음본 파일 위치 : /Users/{사용자이름}/Documents/HighPitch/Audio.YYYYMMDDHHMMSS.m4a
        /// ReturnZero API를 이용해서 UtteranceModel완성
        Task {
            let newUtteranceModels = await makeNewUtterances()
            /// 아무말도 하지 않았을 경우 종료한다.
            if newUtteranceModels.isEmpty {
                print("none of words!")
                return
            }
            /// 시작할 때 프로젝트 세팅이 안되어 있을 경우, 새 프로젝트를 생성 하고, temp에 반영한다.
            /// temp는 새로 만들어진 ProjectModel.persistentModelID 을 들고 있다.
            if projectManager.temp == nil {
                makeNewProject()
            }
            /// 생성한 ID로 프로젝트 모델을 가져온다.
            guard let id = projectManager.temp else { return }
            guard let tempProject = modelContext.model(for: id) as? ProjectModel else { return }
            let newPracticeModel = makeNewPractice(project: tempProject, utterances: newUtteranceModels)
            /// 프로젝트에 추가한다.
            tempProject.practices.append(newPracticeModel)
            
            /// @@@@@@@@ summary를 생성한다. 변경 필요! @@@@@@@@
            practiceManager.current = newPracticeModel
            practiceManager.getPracticeDetail(practice: newPracticeModel)
            /// @@@@@@@@ summary를 생성한다. 변경 필요! @@@@@@@@
            
            projectManager.temp = nil
            
            if projectManager.current == nil {
                projectManager.current = tempProject
            }
            NotificationManager.shared.sendNotification(
                name: practiceManager.current?.practiceName ?? "err"
            )
        }
    }
    
    private func makeNewUtterances() async -> [UtteranceModel] {
        var result: [UtteranceModel] = []
        do {
            let tempUtterances: [Utterance] = try await ReturnzeroAPI()
                .getResult(filePath: mediaManager.getPath(fileName: mediaManager.fileName).path())
            for tempUtterance in tempUtterances {
                result.append(
                    UtteranceModel(
                        startAt: tempUtterance.startAt,
                        duration: tempUtterance.duration,
                        message: tempUtterance.message
                    )
                )
            }
        } catch {
            print(error)
        }
        return result
    }
    
    private func makeNewProject() {
        let newProject = ProjectModel(
            projectName: "\(Date.now.formatted())",
            creatAt: Date.now.formatted(),
            keynotePath: nil,
            keynoteCreation: "temp"
        )
        if let selectedKeynote = keynoteManager.temp {
            newProject.keynoteCreation = selectedKeynote.creation
            newProject.keynotePath = URL(fileURLWithPath: selectedKeynote.path)
            newProject.projectName = selectedKeynote.getFileName()
        }
        modelContext.insert(newProject)
        projectManager.temp = newProject.persistentModelID
    }
    
    private func makeNewPractice(project: ProjectModel, utterances: [UtteranceModel]) -> PracticeModel {
        /// 새 연습 모델을 생성한다.
        let result = PracticeModel(
            practiceName: "init",
            index: -1,
            isVisited: false,
            creatAt: Date().m4aNameToCreateAt(input: mediaManager.fileName),
            audioPath: mediaManager.getPath(fileName: mediaManager.fileName),
            utterances: utterances,
            summary: PracticeSummaryModel()
        )

        if project.practices.count == 0 {
            result.index = 0
            result.practiceName = indexToOrdinalNumber(index: 0)
        } else {
            let latestIndex = project.practices.sorted(by: {$0.creatAt > $1.creatAt}).first?.index
            if let latestIndex = latestIndex {
                result.index = latestIndex + 1
                result.practiceName = indexToOrdinalNumber(index: latestIndex + 1)
            }
        }
        return result
    }
    
    private func indexToOrdinalNumber(index: Int) -> String {
        let ordinalNumber = ["첫", "두", "세", "네", "다섯", "여섯", "일곱", "여덟", "아홉", "열",
                             "열한", "열두", "열세", "열네", "열다섯", "열여섯", "열일곱", "열여덟"]
        
        if ordinalNumber.count < index {
            return "Index 초과"
        }
        return ordinalNumber[index]
    }
            
    private func openSelectedProject() {
        if let selectedProject = selectedProject {
            if selectedProject.projectName != "새 프로젝트" {
                projectManager.current = selectedProject
                if !projectManager.path.isEmpty {
                    projectManager.currentTabItem = 0
                    projectManager.path.removeLast()
                }
                openWindow(id: "main")
            }
        }
    }
    
    private func quitApp() {
        exit(0)
    }
}

// #Preview {
//    @State
//    var selectedProject: ProjectModel = ProjectModel(
//        projectName: "d",
//        creatAt: "d",
//        keynoteCreation: "dd"
//    )
//    return MenubarExtraHeader(selectedProject: $selectedProject)
// }
