#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ============================================================
;  OCR 队列助手  (AutoHotkey v2)
;  队列驱动：OCR 条件 / 鼠标点击或移动 / 延时
; ============================================================

SetWorkingDir A_ScriptDir
CoordMode "Mouse", "Screen"
CoordMode "ToolTip", "Screen"
CoordMode "Pixel", "Screen"
SendMode "Input"
DllCall("LoadLibrary", "Str", "Msftedit.dll")

global APP_TITLE := "OCR 队列助手"
global CONFIG_FILE := A_ScriptDir "\config.ini"
global SERVER_SCRIPT := A_ScriptDir "\ocr-server.ps1"

global steps := []
global selectedIndex := 0
global editingIndex := 0
global editorOpen := false
global running := false
global stopRequested := false

global gStartHotkey := "F9"
global gStopHotkey := "F10"
global serverPid := 0
global serverDir := ""
global serverReady := false
global serverLang := ""
global serverStarting := false
global serverFatal := ""

; GUI controls
global mainGui, lv, loopEdit, startHkEdit, stopHkEdit, minimizeCheck
global startBtn, stopBtn, applyHkBtn, serverText, statusText
global logEdit
global addOcrBtn, addClickBtn, addKeyboardBtn, addDelayBtn, editBtn, delBtn, copyBtn
global upBtn, downBtn, clearBtn, saveCfgBtn, loadCfgBtn

; Editor controls
global editorGui, typeDDL, nameEdit
global xEdit, yEdit, wEdit, hEdit
global btnPickPos, btnPickRegion, btnTestOcr, btnOcrSettings
global conditionModeDDL, exprLabel, exprEdit
global countModeDDL, countEdit, countSuffix, countHint
global text1Edit, text2Edit, text3Edit, text4Edit
global waitEdit, intervalEdit, metDDL, unmetDDL
global ocrActionDDL, btnOcrMouse, ocrMouseSummary
global ocrMouseGui, ocrMouseActionLabel, ocrMouseXEdit, ocrMouseYEdit
global ocrMouseClicksEdit, ocrMouseIntervalEdit, ocrMouseSpeedEdit
global ocrMouseSnapshot := 0
global ocrSettingsGui, ocrLangDDL, ocrScaleDDL, ocrEnhanceDDL, ocrSettingsSnapshot := 0
global keyboardGui, kbNameEdit, kbContentEdit, kbModeDDL, kbRepeatEdit, kbIntervalEdit, kbAfterEdit, kbOKBtn, kbIndex := 0
global keyboardOpen := false
global buttonDDL, clicksEdit, clickIntervalEdit, moveSpeedEdit, clickMetricLabel, clickHint
global mouseGroup, mouseActionLabel, mouseClicksLabel
global delayGroup, delayLabel, delayMs, delayHint
global afterGroup, afterLabel, afterMs, afterHint
global mouseSection := [], delaySection := [], afterSection := []
global editorHeight := 690
global delayEdit, afterEdit, btnOK, btnCancel

; Condition expression parser state
global condExpr := ""
global condPos := 1
global condRefs := []

; Picker
global pickerTarget := ""
global pickerActive := false
global pickerMode := ""
global pickerParent := ""
global pickerArmed := false
global pickerDragging := false
global pickerStartX := 0
global pickerStartY := 0
global pickerPointDown := false
global pickerPointX := 0
global pickerPointY := 0
global pickerOverlay := ""
global pickerHint := ""
global pickerBorders := []

; ============================================================
;  Startup
; ============================================================

OnExit CleanUp

BuildMain()
BuildEditor()
BuildOcrSettingsDialog()
BuildOcrMouseDialog()
BuildKeyboardEditor()
LoadSettings(CONFIG_FILE)
RegisterInitialHotkeys()
RebuildList()

mainGui.Show("w1120 h660")
Log("程序已启动 · 队列 " steps.Length " 步 · " gStartHotkey " 开始 / " gStopHotkey " 停止", "info")
if (steps.Length = 0)
    Log("队列为空：点击「＋ OCR」「＋ 鼠标」「＋ 键盘」「＋ 延时」添加步骤", "muted")

StartOcrServer()
SetTimer(CheckOcrServer, 300)

; ============================================================
;  Main window
; ============================================================

BuildMain() {
    global mainGui, lv, loopEdit, startHkEdit, stopHkEdit, minimizeCheck
    global startBtn, stopBtn, applyHkBtn, serverText, statusText
    global logEdit, addOcrBtn, addClickBtn, addKeyboardBtn, addDelayBtn, editBtn, delBtn, copyBtn
    global upBtn, downBtn, clearBtn, saveCfgBtn, loadCfgBtn

    mainGui := Gui("+MinimizeBox", APP_TITLE)
    mainGui.SetFont("s10", "Microsoft YaHei UI")
    mainGui.MarginX := 10
    mainGui.MarginY := 8
    mainGui.BackColor := "F5F7FA"
    mainGui.OnEvent("Close", Main_Close)

    ; ---- run controls ----
    mainGui.AddGroupBox("x10 y8 w1100 h82", "运行控制")

    mainGui.AddText("x24 y32 w64 h22 +0x200", "循环次数")
    loopEdit := mainGui.AddEdit("x90 y28 w58 h24 Number", "1")
    mainGui.AddText("x154 y32 w70 h22 +0x200", "0 = 无限")

    mainGui.AddText("x238 y32 w82 h22 +0x200", "开始快捷键")
    startHkEdit := mainGui.AddEdit("x322 y28 w80 h24 Center", "F9")
    mainGui.AddText("x414 y32 w82 h22 +0x200", "停止快捷键")
    stopHkEdit := mainGui.AddEdit("x498 y28 w80 h24 Center", "F10")
    applyHkBtn := mainGui.AddButton("x588 y26 w64 h28", "应用")
    applyHkBtn.OnEvent("Click", ApplyHotkeys_UI)
    minimizeCheck := mainGui.AddCheckBox("x668 y28 w160 h24", "运行时最小化窗口")
    minimizeCheck.Value := 1

    startBtn := mainGui.AddButton("x24 y56 w132 h28 Default", "▶ 开始")
    startBtn.OnEvent("Click", (*) => StartQueue())
    stopBtn := mainGui.AddButton("x164 y56 w126 h28", "■ 停止")
    stopBtn.OnEvent("Click", (*) => StopQueue())
    stopBtn.Enabled := false

    serverText := mainGui.AddText("x306 y60 w790 h24 +0x200", "OCR：正在启动…")

    ; ---- queue ----
    mainGui.AddGroupBox("x10 y98 w700 h520", "执行队列")
    lv := mainGui.AddListView("x24 y124 w672 h380 Grid +LV0x20 -Multi", ["#", "名称", "类型", "参数", "后延迟"])
    lv.ModifyCol(1, 38)
    lv.ModifyCol(2, 130)
    lv.ModifyCol(3, 66)
    lv.ModifyCol(4, 352)
    lv.ModifyCol(5, 74)
    lv.OnEvent("ItemSelect", LV_ItemSelect)
    lv.OnEvent("DoubleClick", LV_DoubleClick)

    addOcrBtn := mainGui.AddButton("x24 y514 w90 h30", "＋ OCR")
    addClickBtn := mainGui.AddButton("x120 y514 w90 h30", "＋ 鼠标")
    addKeyboardBtn := mainGui.AddButton("x216 y514 w90 h30", "＋ 键盘")
    addDelayBtn := mainGui.AddButton("x312 y514 w90 h30", "＋ 延时")
    editBtn := mainGui.AddButton("x412 y514 w64 h30", "编辑")
    copyBtn := mainGui.AddButton("x482 y514 w64 h30", "复制")
    delBtn := mainGui.AddButton("x552 y514 w64 h30", "删除")

    upBtn := mainGui.AddButton("x24 y552 w70 h28", "↑ 上移")
    downBtn := mainGui.AddButton("x100 y552 w70 h28", "↓ 下移")
    clearBtn := mainGui.AddButton("x176 y552 w80 h28", "清空队列")
    saveCfgBtn := mainGui.AddButton("x266 y552 w90 h28", "保存配置")
    loadCfgBtn := mainGui.AddButton("x362 y552 w90 h28", "载入配置")
    mainGui.AddText("x468 y557 w220 h22 +0x200", "双击步骤可编辑；OCR 匹配忽略空格")

    addOcrBtn.OnEvent("Click", (*) => OpenEditor("OCR"))
    addClickBtn.OnEvent("Click", (*) => OpenEditor("Click"))
    addKeyboardBtn.OnEvent("Click", (*) => OpenKeyboardEditor(0))
    addDelayBtn.OnEvent("Click", (*) => OpenEditor("Delay"))
    editBtn.OnEvent("Click", (*) => EditSelected())
    copyBtn.OnEvent("Click", (*) => CopySelected())
    delBtn.OnEvent("Click", (*) => DeleteSelected())
    upBtn.OnEvent("Click", (*) => MoveSelected(-1))
    downBtn.OnEvent("Click", (*) => MoveSelected(1))
    clearBtn.OnEvent("Click", (*) => ClearQueue())
    saveCfgBtn.OnEvent("Click", (*) => SaveConfig_UI())
    loadCfgBtn.OnEvent("Click", (*) => LoadConfig_UI())

    ; ---- log ----
    mainGui.AddGroupBox("x720 y98 w390 h520", "运行日志")
    logEdit := mainGui.Add("Custom", "ClassRICHEDIT50W x733 y124 w364 h430 +0x4 +0x40 +VScroll -E0x200", "")
    InitRichLog()
    clr := mainGui.AddButton("x733 y566 w130 h28", "清空日志")
    clr.OnEvent("Click", ClearLog)
    cpy := mainGui.AddButton("x877 y566 w130 h28", "复制日志")
    cpy.OnEvent("Click", CopyLog)
    mainGui.AddText("x733 y602 w340 h20 +0x200", "彩色分级日志 · 保留最近约 400 行")

    statusText := mainGui.AddText("x12 y630 w1090 h22 +0x200", "就绪")

    UpdateButtons()
}

; ============================================================
;  Editor window
; ============================================================

BuildEditor() {
    global editorGui, typeDDL, nameEdit
    global xEdit, yEdit, wEdit, hEdit
    global btnPickPos, btnPickRegion, btnTestOcr, btnOcrSettings
    global conditionModeDDL, exprLabel, exprEdit
    global countModeDDL, countEdit, countSuffix, countHint
    global text1Edit, text2Edit, text3Edit, text4Edit
    global waitEdit, intervalEdit, metDDL, unmetDDL
    global ocrActionDDL, btnOcrMouse, ocrMouseSummary
    global buttonDDL, clicksEdit, clickIntervalEdit, moveSpeedEdit, clickMetricLabel, clickHint
    global mouseGroup, mouseActionLabel, mouseClicksLabel
    global delayGroup, delayLabel, delayMs, delayHint
    global afterGroup, afterLabel, afterMs, afterHint
    global mouseSection, delaySection, afterSection
    global delayEdit, afterEdit, btnOK, btnCancel

    editorGui := Gui("+Owner" mainGui.Hwnd, "编辑步骤")
    editorGui.SetFont("s10", "Microsoft YaHei UI")
    editorGui.MarginX := 14
    editorGui.MarginY := 12
    editorGui.BackColor := "F5F7FA"
    editorGui.OnEvent("Close", Editor_Close)
    editorGui.OnEvent("Escape", (*) => Editor_Close())

    editorGui.AddText("x14 y18 w56 h22 +0x200", "步骤类型")
    typeDDL := editorGui.AddDropDownList("x72 y14 w170", ["OCR 检测", "鼠标操作", "延时"])
    typeDDL.OnEvent("Change", (*) => ApplyEditorType())
    editorGui.AddText("x264 y18 w62 h22 +0x200", "步骤名称")
    nameEdit := editorGui.AddEdit("x330 y14 w296 h24")

    ; ---- position / region ----
    editorGui.AddGroupBox("x14 y48 w622 h118", "位置与区域（屏幕物理像素）")
    editorGui.AddText("x28 y78 w18 h22 +0x200", "X")
    xEdit := editorGui.AddEdit("x48 y74 w72 h24")
    editorGui.AddText("x132 y78 w18 h22 +0x200", "Y")
    yEdit := editorGui.AddEdit("x152 y74 w72 h24")
    editorGui.AddText("x232 y78 w22 h22 +0x200", "宽")
    wEdit := editorGui.AddEdit("x256 y74 w72 h24 Number")
    editorGui.AddText("x336 y78 w22 h22 +0x200", "高")
    hEdit := editorGui.AddEdit("x360 y74 w72 h24 Number")

    btnPickPos := editorGui.AddButton("x28 y106 w120 h28", "拾取坐标")
    btnPickPos.OnEvent("Click", (*) => PickPoint())
    btnPickRegion := editorGui.AddButton("x156 y106 w140 h28", "框选 OCR 区域")
    btnPickRegion.OnEvent("Click", (*) => PickRegion())
    btnTestOcr := editorGui.AddButton("x304 y106 w100 h28", "测试 OCR")
    btnTestOcr.OnEvent("Click", (*) => TestOcr())
    btnOcrSettings := editorGui.AddButton("x414 y106 w120 h28", "识别设置…")
    btnOcrSettings.OnEvent("Click", (*) => OpenOcrSettingsDialog())

    ; ---- OCR condition ----
    editorGui.AddGroupBox("x14 y174 w622 h222", "OCR 文字条件")
    editorGui.AddText("x28 y200 w64 h22 +0x200", "条件模式")
    conditionModeDDL := editorGui.AddDropDownList("x94 y196 w170", ["任一命中（或）", "全部命中（且）", "自定义表达式", "满足指定项数"])
    conditionModeDDL.OnEvent("Change", (*) => UpdateOcrExpressionUI())
    exprLabel := editorGui.AddText("x266 y200 w48 h22 +0x200", "表达式")
    exprEdit := editorGui.AddEdit("x320 y196 w290 h24")
    SendMessage(0x1501, 1, StrPtr("例如：(1或2)且(3且4)"), exprEdit.Hwnd)

    countModeDDL := editorGui.AddDropDownList("x320 y196 w64", ["至少", "恰好"])
    countEdit := editorGui.AddEdit("x390 y196 w36 h24 Number", "3")
    countSuffix := editorGui.AddText("x432 y200 w20 h22 +0x200", "项")
    countHint := editorGui.AddText("x456 y200 w154 h22 +0x200", "已填 0 项")
    for ctl in [countModeDDL, countEdit, countSuffix, countHint]
        ctl.Visible := false

    editorGui.AddText("x28 y234 w48 h22 +0x200", "文字1")
    text1Edit := editorGui.AddEdit("x80 y230 w240 h24")
    editorGui.AddText("x332 y234 w48 h22 +0x200", "文字2")
    text2Edit := editorGui.AddEdit("x384 y230 w226 h24")
    editorGui.AddText("x28 y268 w48 h22 +0x200", "文字3")
    text3Edit := editorGui.AddEdit("x80 y264 w240 h24")
    editorGui.AddText("x332 y268 w48 h22 +0x200", "文字4")
    text4Edit := editorGui.AddEdit("x384 y264 w226 h24")
    for ctl in [text1Edit, text2Edit, text3Edit, text4Edit]
        ctl.OnEvent("Change", (*) => UpdateAutoExpression())
    editorGui.AddText("x28 y300 w68 h22 +0x200", "满足后鼠标")
    ocrActionDDL := editorGui.AddDropDownList("x100 y296 w116", ["无动作", "左键点击", "右键点击", "仅移动"])
    ocrActionDDL.OnEvent("Change", (*) => UpdateOcrMouseUI())
    btnOcrMouse := editorGui.AddButton("x222 y295 w80 h26", "设置…")
    btnOcrMouse.OnEvent("Click", (*) => OpenOcrMouseDialog())
    ocrMouseSummary := editorGui.AddText("x308 y300 w302 h22 +0x200", "不执行鼠标动作")

    editorGui.AddText("x28 y330 w60 h22 +0x200", "最长等待")
    waitEdit := editorGui.AddEdit("x92 y326 w56 h24 Number", "0")
    editorGui.AddText("x152 y330 w20 h22 +0x200", "ms")
    editorGui.AddText("x184 y330 w60 h22 +0x200", "检测间隔")
    intervalEdit := editorGui.AddEdit("x248 y326 w56 h24 Number", "250")
    editorGui.AddText("x308 y330 w20 h22 +0x200", "ms")
    editorGui.AddText("x340 y330 w48 h22 +0x200", "满足后")
    metDDL := editorGui.AddDropDownList("x392 y326 w112", ["继续下一步", "停止队列"])

    editorGui.AddText("x28 y360 w64 h22 +0x200", "不满足后")
    unmetDDL := editorGui.AddDropDownList("x94 y356 w130", ["继续下一步", "停止队列"])
    editorGui.AddText("x232 y360 w378 h22 +0x200", "不满足会按间隔重试到超时，再执行此动作")

    ; ---- mouse ----
    mouseGroup := editorGui.AddGroupBox("x14 y404 w622 h96", "鼠标操作")
    mouseActionLabel := editorGui.AddText("x28 y430 w44 h22 +0x200", "动作")
    buttonDDL := editorGui.AddDropDownList("x74 y426 w116", ["左键点击", "右键点击", "仅移动"])
    buttonDDL.OnEvent("Change", (*) => ApplyEditorType())
    mouseClicksLabel := editorGui.AddText("x206 y430 w62 h22 +0x200", "点击次数")
    clicksEdit := editorGui.AddEdit("x272 y426 w52 h24 Number", "1")
    clickMetricLabel := editorGui.AddText("x336 y430 w104 h22 +0x200", "每次间隔(ms)")
    clickIntervalEdit := editorGui.AddEdit("x444 y426 w70 h24 Number", "80")
    moveSpeedEdit := editorGui.AddEdit("x444 y426 w70 h24 Number", "0")
    moveSpeedEdit.Visible := false
    clickHint := editorGui.AddText("x74 y458 w530 h20 +0x200", "点击坐标为屏幕像素；延迟计时期间按停止键可立即中断。")

    ; ---- delay ----
    delayGroup := editorGui.AddGroupBox("x14 y508 w622 h72", "延时")
    delayLabel := editorGui.AddText("x28 y534 w58 h22 +0x200", "延时")
    delayEdit := editorGui.AddEdit("x100 y530 w100 h24 Number", "1000")
    delayMs := editorGui.AddText("x208 y534 w24 h22 +0x200", "ms")
    delayHint := editorGui.AddText("x252 y534 w340 h22 +0x200", "只在本步为「延时」类型时生效。")

    ; ---- after ----
    afterGroup := editorGui.AddGroupBox("x14 y588 w622 h58", "动作完成后")
    afterLabel := editorGui.AddText("x28 y612 w112 h22 +0x200", "本步执行后延迟")
    afterEdit := editorGui.AddEdit("x148 y606 w80 h24 Number", "300")
    afterMs := editorGui.AddText("x236 y612 w24 h22 +0x200", "ms")
    afterHint := editorGui.AddText("x270 y612 w340 h20 +0x200", "每个动作结束后等待，0 表示不等待")

    btnOK := editorGui.AddButton("x432 y656 w96 h30 Default", "添加步骤")
    btnOK.OnEvent("Click", Editor_OK)
    btnCancel := editorGui.AddButton("x538 y656 w96 h30", "取消")
    btnCancel.OnEvent("Click", (*) => Editor_Close())

    mouseSection := [mouseGroup, mouseActionLabel, buttonDDL, mouseClicksLabel, clicksEdit, clickMetricLabel, clickIntervalEdit, moveSpeedEdit, clickHint]
    delaySection := [delayGroup, delayLabel, delayEdit, delayMs, delayHint]
    afterSection := [afterGroup, afterLabel, afterEdit, afterMs, afterHint]

    ApplyEditorType()
}

ApplyEditorType(*) {
    global typeDDL, xEdit, yEdit, wEdit, hEdit, btnPickPos, btnPickRegion, btnTestOcr, btnOcrSettings
    global conditionModeDDL, exprLabel, exprEdit
    global countModeDDL, countEdit, countSuffix, countHint
    global text1Edit, text2Edit, text3Edit, text4Edit
    global waitEdit, intervalEdit, metDDL, unmetDDL
    global ocrActionDDL, btnOcrMouse, ocrMouseSummary
    global buttonDDL, clicksEdit, clickIntervalEdit, moveSpeedEdit, clickMetricLabel, clickHint
    global delayEdit

    idx := typeDDL.Value
    if (idx < 1 || idx > 3)
        idx := 1
    t := TypeFromIndex(idx)
    isOcr := (t = "OCR")
    isClick := (t = "Click")
    isDelay := (t = "Delay")

    action := buttonDDL.Value
    isMove := isClick && (action = 3)

    xEdit.Enabled := !isDelay
    yEdit.Enabled := !isDelay
    wEdit.Enabled := isOcr
    hEdit.Enabled := isOcr
    btnPickPos.Enabled := !isDelay
    btnPickRegion.Enabled := isOcr
    btnTestOcr.Enabled := isOcr
    btnOcrSettings.Enabled := isOcr

    conditionModeDDL.Enabled := isOcr
    text1Edit.Enabled := isOcr
    text2Edit.Enabled := isOcr
    text3Edit.Enabled := isOcr
    text4Edit.Enabled := isOcr
    waitEdit.Enabled := isOcr
    intervalEdit.Enabled := isOcr
    metDDL.Enabled := isOcr
    unmetDDL.Enabled := isOcr
    ocrActionDDL.Enabled := isOcr

    buttonDDL.Enabled := isClick
    clicksEdit.Enabled := isClick && !isMove
    clickIntervalEdit.Enabled := isClick
    clickIntervalEdit.Visible := isClick && !isMove
    moveSpeedEdit.Visible := isClick && isMove
    moveSpeedEdit.Enabled := isClick
    clickMetricLabel.Text := isMove ? "移动速度" : "每次间隔(ms)"
    clickHint.Text := isMove
        ? "仅移动不点击；速度 0 = 瞬间，1-100 = 相对速度。"
        : "点击坐标为屏幕像素；延迟计时期间按停止键可立即中断。"

    delayEdit.Enabled := isDelay

    UpdateOcrExpressionUI()
    UpdateOcrMouseUI()
    LayoutEditorSections(isOcr, isMove)
}

LayoutEditorSections(isOcr, isMove) {
    global mouseSection, delaySection, afterSection
    global afterGroup, afterLabel, afterEdit, afterMs, afterHint
    global btnOK, btnCancel, editorHeight, editorOpen, editorGui
    global clickIntervalEdit, moveSpeedEdit

    for ctl in mouseSection
        ctl.Visible := !isOcr
    for ctl in delaySection
        ctl.Visible := !isOcr

    if (!isOcr) {
        clickIntervalEdit.Visible := !isMove
        moveSpeedEdit.Visible := isMove
    }

    if (isOcr) {
        afterGroup.Move(14, 404)
        afterLabel.Move(28, 428)
        afterEdit.Move(148, 422)
        afterMs.Move(236, 428)
        afterHint.Move(270, 428)
        btnOK.Move(432, 472)
        btnCancel.Move(538, 472)
        editorHeight := 510
    } else {
        afterGroup.Move(14, 588)
        afterLabel.Move(28, 612)
        afterEdit.Move(148, 606)
        afterMs.Move(236, 612)
        afterHint.Move(270, 612)
        btnOK.Move(432, 656)
        btnCancel.Move(538, 656)
        editorHeight := 690
    }

    if (editorOpen)
        editorGui.Show("w650 h" editorHeight)
}

UpdateOcrExpressionUI() {
    global typeDDL, conditionModeDDL, exprLabel, exprEdit
    global countModeDDL, countEdit, countSuffix, countHint

    isOcr := (TypeFromIndex(typeDDL.Value) = "OCR")
    if (!isOcr) {
        exprLabel.Visible := true
        exprEdit.Visible := true
        exprEdit.Enabled := false
        for ctl in [countModeDDL, countEdit, countSuffix, countHint]
            ctl.Visible := false
        countModeDDL.Enabled := false
        countEdit.Enabled := false
        return
    }

    mode := conditionModeDDL.Value
    if (mode < 1 || mode > 4)
        mode := 1

    if (mode = 4) {
        exprLabel.Visible := false
        exprEdit.Visible := false
        for ctl in [countModeDDL, countEdit, countSuffix, countHint]
            ctl.Visible := true
        countModeDDL.Enabled := true
        countEdit.Enabled := true
        UpdateCountHint()
        return
    }

    exprLabel.Visible := true
    exprEdit.Visible := true
    for ctl in [countModeDDL, countEdit, countSuffix, countHint]
        ctl.Visible := false
    countModeDDL.Enabled := false
    countEdit.Enabled := false

    if (mode = 3) {
        exprEdit.Opt("-ReadOnly")
        exprEdit.Enabled := true
    } else {
        exprEdit.Opt("+ReadOnly")
        exprEdit.Value := BuildSimpleExpressionFromEditor(mode)
        exprEdit.Enabled := true
    }
}

UpdateAutoExpression(*) {
    global typeDDL, conditionModeDDL, exprEdit

    if (TypeFromIndex(typeDDL.Value) != "OCR")
        return
    mode := conditionModeDDL.Value
    if (mode = 4) {
        UpdateCountHint()
        return
    }
    if (mode != 1 && mode != 2)
        return
    exprEdit.Value := BuildSimpleExpressionFromEditor(mode)
}

UpdateCountHint() {
    global countHint
    filled := CountFilledEditorTerms()
    countHint.Text := "已填 " filled " 项"
    countHint.SetFont(filled > 0 ? "c555555" : "cB26B00")
}

CountFilledEditorTerms() {
    global text1Edit, text2Edit, text3Edit, text4Edit
    n := 0
    for ctl in [text1Edit, text2Edit, text3Edit, text4Edit] {
        if (Trim(ctl.Value) != "")
            n++
    }
    return n
}

BuildSimpleExpressionFromEditor(mode) {
    global text1Edit, text2Edit, text3Edit, text4Edit
    return BuildSimpleExpression(mode, [text1Edit.Value, text2Edit.Value, text3Edit.Value, text4Edit.Value])
}

UpdateOcrMouseUI(*) {
    global typeDDL, ocrActionDDL, btnOcrMouse, ocrMouseSummary
    global ocrMouseXEdit, ocrMouseYEdit, ocrMouseClicksEdit, ocrMouseSpeedEdit

    isOcr := (TypeFromIndex(typeDDL.Value) = "OCR")
    if (!isOcr) {
        btnOcrMouse.Enabled := false
        ocrMouseSummary.Text := ""
        return
    }

    act := OcrActionFromIndex(ocrActionDDL.Value)
    if (act = "None") {
        btnOcrMouse.Enabled := false
        ocrMouseSummary.Text := "不执行鼠标动作"
        return
    }

    btnOcrMouse.Enabled := true
    if !IsObject(ocrMouseXEdit) {
        ocrMouseSummary.Text := OcrActionLabel(act)
        return
    }

    x := ocrMouseXEdit.Value
    y := ocrMouseYEdit.Value
    if (act = "Move")
        ocrMouseSummary.Text := "移动到 (" x "," y ") · 速度 " ocrMouseSpeedEdit.Value
    else
        ocrMouseSummary.Text := OcrActionLabel(act) " (" x "," y ") ×" ocrMouseClicksEdit.Value
}

OcrActionFromIndex(i) {
    return (i = 2) ? "Left" : (i = 3) ? "Right" : (i = 4) ? "Move" : "None"
}

OcrActionIndex(a) {
    return (a = "Left") ? 2 : (a = "Right") ? 3 : (a = "Move") ? 4 : 1
}

OcrActionLabel(a) {
    return (a = "Left") ? "左键点击" : (a = "Right") ? "右键点击" : (a = "Move") ? "仅移动" : "无动作"
}

BuildOcrMouseDialog() {
    global editorGui, ocrMouseGui, ocrMouseActionLabel
    global ocrMouseXEdit, ocrMouseYEdit
    global ocrMouseClicksEdit, ocrMouseIntervalEdit, ocrMouseSpeedEdit

    ocrMouseGui := Gui("+Owner" editorGui.Hwnd, "满足后鼠标动作")
    ocrMouseGui.SetFont("s10", "Microsoft YaHei UI")
    ocrMouseGui.MarginX := 12
    ocrMouseGui.MarginY := 10
    ocrMouseGui.BackColor := "F5F7FA"
    ocrMouseGui.OnEvent("Close", (*) => CancelOcrMouseDialog())
    ocrMouseGui.OnEvent("Escape", (*) => CancelOcrMouseDialog())

    ocrMouseActionLabel := ocrMouseGui.AddText("x16 y14 w440 h24 +0x200", "动作：")

    ocrMouseGui.AddGroupBox("x16 y46 w448 h90", "目标坐标（屏幕像素）")
    ocrMouseGui.AddText("x30 y74 w18 h22 +0x200", "X")
    ocrMouseXEdit := ocrMouseGui.AddEdit("x50 y70 w80 h24")
    ocrMouseGui.AddText("x150 y74 w18 h22 +0x200", "Y")
    ocrMouseYEdit := ocrMouseGui.AddEdit("x170 y70 w80 h24")
    pickBtn := ocrMouseGui.AddButton("x270 y69 w110 h26", "拾取坐标")
    pickBtn.OnEvent("Click", (*) => PickOcrMousePoint())

    ocrMouseGui.AddGroupBox("x16 y146 w448 h92", "点击 / 移动参数")
    ocrMouseGui.AddText("x30 y176 w62 h22 +0x200", "点击次数")
    ocrMouseClicksEdit := ocrMouseGui.AddEdit("x98 y172 w56 h24 Number", "1")
    ocrMouseGui.AddText("x176 y176 w92 h22 +0x200", "每次间隔(ms)")
    ocrMouseIntervalEdit := ocrMouseGui.AddEdit("x274 y172 w66 h24 Number", "80")
    ocrMouseGui.AddText("x30 y206 w62 h22 +0x200", "移动速度")
    ocrMouseSpeedEdit := ocrMouseGui.AddEdit("x98 y202 w56 h24 Number", "0")
    ocrMouseGui.AddText("x164 y206 w286 h22 +0x200", "0=瞬间，1-100=相对速度（数字越大越慢）")

    ok := ocrMouseGui.AddButton("x282 y252 w80 h30 Default", "确定")
    ok.OnEvent("Click", (*) => ConfirmOcrMouseDialog())
    cancel := ocrMouseGui.AddButton("x372 y252 w80 h30", "取消")
    cancel.OnEvent("Click", (*) => CancelOcrMouseDialog())

    UpdateOcrMouseUI()
}

OpenOcrMouseDialog() {
    global editorGui, ocrMouseGui, ocrMouseActionLabel, ocrActionDDL
    global ocrMouseXEdit, ocrMouseYEdit, ocrMouseClicksEdit, ocrMouseIntervalEdit, ocrMouseSpeedEdit
    global ocrMouseSnapshot

    act := OcrActionFromIndex(ocrActionDDL.Value)
    if (act = "None") {
        MsgBox("请先在“满足后鼠标”中选择左键点击、右键点击或仅移动。", "提示", "Iconi")
        return
    }

    ocrMouseActionLabel.Text := "动作：" OcrActionLabel(act) "（条件满足后执行）"
    isMove := (act = "Move")
    ocrMouseClicksEdit.Enabled := !isMove
    ocrMouseIntervalEdit.Enabled := !isMove
    ocrMouseSpeedEdit.Enabled := isMove

    ocrMouseSnapshot := {
        x: ocrMouseXEdit.Value,
        y: ocrMouseYEdit.Value,
        clicks: ocrMouseClicksEdit.Value,
        interval: ocrMouseIntervalEdit.Value,
        speed: ocrMouseSpeedEdit.Value
    }

    ocrMouseGui.Show("w480 h300 Center")
}

ConfirmOcrMouseDialog() {
    global ocrMouseXEdit, ocrMouseYEdit, ocrMouseClicksEdit, ocrMouseIntervalEdit, ocrMouseSpeedEdit
    global ocrMouseGui, ocrActionDDL

    try {
        x := RequireInt(ocrMouseXEdit.Value, "鼠标 X 坐标", -100000, 100000)
        y := RequireInt(ocrMouseYEdit.Value, "鼠标 Y 坐标", -100000, 100000)
        ValidatePoint(x, y)
        if (OcrActionFromIndex(ocrActionDDL.Value) = "Move") {
            RequireInt(ocrMouseSpeedEdit.Value, "移动速度", 0, 100)
        } else {
            RequireInt(ocrMouseClicksEdit.Value, "点击次数", 1, 100)
            RequireInt(ocrMouseIntervalEdit.Value, "点击间隔", 0, 3600000)
        }
    } catch as e {
        MsgBox(e.Message, "鼠标动作", "Icon!")
        return
    }

    ocrMouseGui.Hide()
    UpdateOcrMouseUI()
}

CancelOcrMouseDialog(*) {
    global ocrMouseGui, ocrMouseSnapshot
    global ocrMouseXEdit, ocrMouseYEdit, ocrMouseClicksEdit, ocrMouseIntervalEdit, ocrMouseSpeedEdit

    if IsObject(ocrMouseSnapshot) {
        ocrMouseXEdit.Value := ocrMouseSnapshot.x
        ocrMouseYEdit.Value := ocrMouseSnapshot.y
        ocrMouseClicksEdit.Value := ocrMouseSnapshot.clicks
        ocrMouseIntervalEdit.Value := ocrMouseSnapshot.interval
        ocrMouseSpeedEdit.Value := ocrMouseSnapshot.speed
        ocrMouseSnapshot := 0
    }
    ocrMouseGui.Hide()
    UpdateOcrMouseUI()
}

PickOcrMousePoint(*) {
    global ocrMouseGui
    StartPicker("point", ocrMouseGui, "ocrMouse")
}

OcrLanguageFromIndex(i) {
    return (i = 2) ? "zh" : (i = 3) ? "en" : (i = 4) ? "mixed" : "auto"
}

OcrLanguageIndex(v) {
    return (v = "zh") ? 2 : (v = "en") ? 3 : (v = "mixed") ? 4 : 1
}

OcrLanguageLabel(v) {
    return (v = "zh") ? "中文简体" : (v = "en") ? "英文" : (v = "mixed") ? "中文+英文" : "自动"
}

OcrEnhanceFromIndex(i) {
    return (i = 2) ? "gray" : (i = 3) ? "contrast" : "none"
}

OcrEnhanceLabel(v) {
    return (v = "gray") ? "灰度" : (v = "contrast") ? "增强对比度" : "原图"
}

OcrEnhanceIndex(v) {
    return (v = "gray") ? 2 : (v = "contrast") ? 3 : 1
}

BuildOcrSettingsDialog() {
    global editorGui, ocrSettingsGui, ocrLangDDL, ocrScaleDDL, ocrEnhanceDDL

    ocrSettingsGui := Gui("+Owner" editorGui.Hwnd, "OCR 识别设置")
    ocrSettingsGui.SetFont("s10", "Microsoft YaHei UI")
    ocrSettingsGui.MarginX := 14
    ocrSettingsGui.MarginY := 12
    ocrSettingsGui.BackColor := "F5F7FA"
    ocrSettingsGui.OnEvent("Close", (*) => CancelOcrSettingsDialog())
    ocrSettingsGui.OnEvent("Escape", (*) => CancelOcrSettingsDialog())

    ocrSettingsGui.AddGroupBox("x14 y10 w440 h190", "识别参数")
    ocrSettingsGui.AddText("x30 y42 w80 h22 +0x200", "识别语言")
    ocrLangDDL := ocrSettingsGui.AddDropDownList("x116 y38 w300", ["自动（默认中文）", "仅中文简体", "仅英文", "中文+英文"])

    ocrSettingsGui.AddText("x30 y82 w80 h22 +0x200", "图像放大")
    ocrScaleDDL := ocrSettingsGui.AddDropDownList("x116 y78 w300", ["1 倍（原尺寸）", "2 倍放大", "3 倍放大"])

    ocrSettingsGui.AddText("x30 y122 w80 h22 +0x200", "图像处理")
    ocrEnhanceDDL := ocrSettingsGui.AddDropDownList("x116 y118 w300", ["原图", "灰度", "增强对比度"])

    ocrSettingsGui.AddText("x30 y154 w410 h24 +0x200",
        "语言、放大和处理会同时用于“测试 OCR”和队列。")

    ok := ocrSettingsGui.AddButton("x258 y216 w90 h30 Default", "确定")
    ok.OnEvent("Click", (*) => ConfirmOcrSettingsDialog())
    cancel := ocrSettingsGui.AddButton("x360 y216 w90 h30", "取消")
    cancel.OnEvent("Click", (*) => CancelOcrSettingsDialog())
}

OpenOcrSettingsDialog() {
    global typeDDL, ocrSettingsGui, ocrLangDDL, ocrScaleDDL, ocrEnhanceDDL, ocrSettingsSnapshot

    if (TypeFromIndex(typeDDL.Value) != "OCR")
        return

    ocrSettingsSnapshot := {
        lang: ocrLangDDL.Value,
        scale: ocrScaleDDL.Value,
        enhance: ocrEnhanceDDL.Value
    }
    ocrSettingsGui.Show("w480 h270 Center")
}

ConfirmOcrSettingsDialog(*) {
    global ocrSettingsGui
    ocrSettingsGui.Hide()
}

CancelOcrSettingsDialog(*) {
    global ocrSettingsGui, ocrSettingsSnapshot, ocrLangDDL, ocrScaleDDL, ocrEnhanceDDL

    if IsObject(ocrSettingsSnapshot) {
        ocrLangDDL.Value := ocrSettingsSnapshot.lang
        ocrScaleDDL.Value := ocrSettingsSnapshot.scale
        ocrEnhanceDDL.Value := ocrSettingsSnapshot.enhance
        ocrSettingsSnapshot := 0
    }
    ocrSettingsGui.Hide()
}

GetEditorOcrSettings() {
    global ocrLangDDL, ocrScaleDDL, ocrEnhanceDDL
    return {
        language: OcrLanguageFromIndex(ocrLangDDL.Value),
        scale: ocrScaleDDL.Value,
        enhance: OcrEnhanceFromIndex(ocrEnhanceDDL.Value)
    }
}

BuildKeyboardEditor() {
    global mainGui, keyboardGui, kbNameEdit, kbContentEdit, kbModeDDL, kbRepeatEdit, kbIntervalEdit, kbAfterEdit, kbOKBtn

    keyboardGui := Gui("+Owner" mainGui.Hwnd, "键盘操作")
    keyboardGui.SetFont("s10", "Microsoft YaHei UI")
    keyboardGui.MarginX := 12
    keyboardGui.MarginY := 10
    keyboardGui.BackColor := "F5F7FA"
    keyboardGui.OnEvent("Close", (*) => Keyboard_Close())
    keyboardGui.OnEvent("Escape", (*) => Keyboard_Close())

    keyboardGui.AddText("x16 y14 w62 h22 +0x200", "步骤名称")
    kbNameEdit := keyboardGui.AddEdit("x90 y10 w440 h24")
    keyboardGui.AddText("x16 y48 w62 h22 +0x200", "按键/文本")
    kbContentEdit := keyboardGui.AddEdit("x90 y44 w440 h24")
    keyboardGui.AddText("x16 y82 w62 h22 +0x200", "发送方式")
    kbModeDDL := keyboardGui.AddDropDownList("x90 y78 w300", ["按键语法（支持 {Enter}、^c）", "原样文本"])

    keyboardGui.AddText("x16 y116 w62 h22 +0x200", "重复次数")
    kbRepeatEdit := keyboardGui.AddEdit("x90 y112 w56 h24 Number", "1")
    keyboardGui.AddText("x164 y116 w64 h22 +0x200", "间隔(ms)")
    kbIntervalEdit := keyboardGui.AddEdit("x236 y112 w64 h24 Number", "100")
    keyboardGui.AddText("x318 y116 w64 h22 +0x200", "执行后延迟")
    kbAfterEdit := keyboardGui.AddEdit("x392 y112 w64 h24 Number", "300")
    keyboardGui.AddText("x460 y116 w24 h22 +0x200", "ms")

    keyboardGui.AddText("x16 y150 w510 h24 +0x200",
        "示例：{Enter}、{Tab}、^c、!{F4}；原样文本不解释这些符号。")

    kbOKBtn := keyboardGui.AddButton("x330 y214 w96 h30 Default", "添加步骤")
    kbOKBtn.OnEvent("Click", (*) => Keyboard_OK())
    cancel := keyboardGui.AddButton("x436 y214 w96 h30", "取消")
    cancel.OnEvent("Click", (*) => Keyboard_Close())
}

OpenKeyboardEditor(index := 0) {
    global keyboardGui, keyboardOpen, editorOpen, pickerActive, kbIndex, running, steps, editorGui
    global kbNameEdit, kbContentEdit, kbModeDDL, kbRepeatEdit, kbIntervalEdit, kbAfterEdit, kbOKBtn

    if running {
        MsgBox("队列正在运行，请先停止后再编辑。", "提示", "Iconi")
        return
    }
    if (pickerActive)
        return
    if (editorOpen) {
        WinActivate editorGui
        return
    }
    if (keyboardOpen) {
        WinActivate keyboardGui
        return
    }

    kbIndex := index
    if (index >= 1) {
        s := steps[index]
        if (s.type != "Keyboard")
            return
    } else {
        s := NewStep("Keyboard")
    }

    keyboardGui.Title := (index >= 1) ? ("编辑键盘步骤 #" index) : "添加键盘步骤"
    kbOKBtn.Text := (index >= 1) ? "保存修改" : "添加步骤"
    kbNameEdit.Value := s.name
    kbContentEdit.Value := s.keys
    kbModeDDL.Value := (s.keyMode = "text") ? 2 : 1
    kbRepeatEdit.Value := s.keyRepeats
    kbIntervalEdit.Value := s.keyInterval
    kbAfterEdit.Value := s.after
    keyboardGui.Show("w550 h260 Center")
    keyboardOpen := true
    kbContentEdit.Focus()
}

Keyboard_Close(*) {
    global keyboardGui, keyboardOpen, mainGui
    keyboardGui.Hide()
    keyboardOpen := false
    mainGui.Show()
    WinActivate mainGui
}

Keyboard_OK(*) {
    global keyboardGui, keyboardOpen, kbIndex, selectedIndex, steps, mainGui
    global kbNameEdit, kbContentEdit, kbModeDDL, kbRepeatEdit, kbIntervalEdit, kbAfterEdit

    try {
        content := kbContentEdit.Value
        if (content = "")
            throw ValueError("按键/文本不能为空。")
        repeats := RequireInt(kbRepeatEdit.Value, "重复次数", 1, 9999)
        interval := RequireInt(kbIntervalEdit.Value, "间隔", 0, 3600000)
        after := RequireInt(kbAfterEdit.Value, "执行后延迟", 0, 3600000)
    } catch as e {
        MsgBox(e.Message, "键盘操作", "Icon!")
        return
    }

    s := NewStep("Keyboard")
    s.keys := content
    s.keyMode := (kbModeDDL.Value = 2) ? "text" : "send"
    s.keyRepeats := repeats
    s.keyInterval := interval
    s.after := after
    s.name := Trim(kbNameEdit.Value)
    if (s.name = "")
        s.name := (s.keyMode = "text" ? "输入：" : "按键：") PreviewText(content, 40)

    if (kbIndex >= 1) {
        steps[kbIndex] := s
        selectedIndex := kbIndex
        Log("已修改键盘步骤 #" kbIndex " · " s.name, "info")
    } else {
        steps.Push(s)
        selectedIndex := steps.Length
        Log("已添加键盘步骤 #" selectedIndex " · " s.name, "info")
    }

    SaveConfig()
    RebuildList()
    keyboardGui.Hide()
    keyboardOpen := false
    mainGui.Show()
    WinActivate mainGui
    UpdateButtons()
}

OpenEditor(type, index := 0) {
    global editorGui, editingIndex, editorOpen, editorHeight, btnOK, typeDDL, nameEdit, keyboardOpen, keyboardGui
    global xEdit, yEdit, wEdit, hEdit, conditionModeDDL, exprLabel, exprEdit
    global countModeDDL, countEdit, countSuffix, countHint
    global text1Edit, text2Edit, text3Edit, text4Edit
    global waitEdit, intervalEdit, metDDL, unmetDDL
    global ocrActionDDL, btnOcrMouse, ocrMouseSummary, ocrMouseGui
    global ocrMouseXEdit, ocrMouseYEdit, ocrMouseClicksEdit, ocrMouseIntervalEdit, ocrMouseSpeedEdit
    global ocrSettingsGui, ocrLangDDL, ocrScaleDDL, ocrEnhanceDDL
    global buttonDDL, clicksEdit, clickIntervalEdit, moveSpeedEdit, delayEdit, afterEdit

    if running {
        MsgBox("队列正在运行，请先停止后再编辑。", "提示", "Iconi")
        return
    }
    if (type = "Keyboard") {
        OpenKeyboardEditor(index)
        return
    }
    if (editorOpen) {
        WinActivate editorGui
        return
    }
    if (keyboardOpen) {
        WinActivate keyboardGui
        return
    }

    editingIndex := index
    if (index >= 1) {
        s := steps[index]
        type := s.type
    } else {
        s := NewStep(type)
    }

    typeDDL.Value := TypeIndex(type)
    nameEdit.Value := s.name
    xEdit.Value := s.x
    yEdit.Value := s.y
    wEdit.Value := s.w
    hEdit.Value := s.h
    text1Edit.Value := s.text1
    text2Edit.Value := s.text2
    text3Edit.Value := s.text3
    text4Edit.Value := s.text4
    conditionModeDDL.Value := GetStepConditionMode(s)
    exprEdit.Value := s.expression
    countModeDDL.Value := (s.countMode = "exactly") ? 2 : 1
    countEdit.Value := s.requiredCount
    ocrLangDDL.Value := OcrLanguageIndex(s.ocrLanguage)
    scaleValue := s.ocrScale
    if (scaleValue < 1 || scaleValue > 3)
        scaleValue := 1
    ocrScaleDDL.Value := scaleValue
    ocrEnhanceDDL.Value := OcrEnhanceIndex(s.ocrEnhance)
    ocrActionDDL.Value := OcrActionIndex(s.mouseAction)
    ocrMouseXEdit.Value := s.mouseX
    ocrMouseYEdit.Value := s.mouseY
    ocrMouseClicksEdit.Value := s.mouseClicks
    ocrMouseIntervalEdit.Value := s.mouseClickInterval
    ocrMouseSpeedEdit.Value := s.mouseMoveSpeed
    waitEdit.Value := s.wait
    intervalEdit.Value := s.interval
    metDDL.Value := (s.metAction = "stop") ? 2 : 1
    unmetDDL.Value := (s.unmetAction = "continue") ? 1 : 2
    buttonDDL.Value := (s.button = "Right") ? 2 : (s.button = "Move") ? 3 : 1
    clicksEdit.Value := s.clicks
    clickIntervalEdit.Value := s.clickInterval
    moveSpeedEdit.Value := s.moveSpeed
    delayEdit.Value := s.delay
    afterEdit.Value := s.after

    ApplyEditorType()
    UpdateOcrExpressionUI()
    editorGui.Title := (index >= 1) ? ("编辑步骤 #" index) : ("添加步骤 - " TypeLabel(type))
    btnOK.Text := (index >= 1) ? "保存修改" : "添加步骤"
    editorOpen := true
    if IsObject(ocrMouseGui)
        ocrMouseGui.Hide()
    if IsObject(ocrSettingsGui)
        ocrSettingsGui.Hide()
    editorGui.Show("w650 h" editorHeight " Center")
    nameEdit.Focus()
}

Editor_Close(*) {
    global editorGui, editorOpen, ocrMouseGui, ocrSettingsGui
    if IsObject(ocrMouseGui)
        ocrMouseGui.Hide()
    if IsObject(ocrSettingsGui)
        ocrSettingsGui.Hide()
    editorGui.Hide()
    editorOpen := false
    mainGui.Show()
    WinActivate mainGui
}

Editor_OK(*) {
    global editorGui, editorOpen, editingIndex, selectedIndex, steps, ocrMouseGui, ocrSettingsGui

    try s := CollectEditor()
    catch as e {
        MsgBox(e.Message, "无法保存步骤", "Icon!")
        return
    }

    if (editingIndex >= 1) {
        steps[editingIndex] := s
        selectedIndex := editingIndex
        Log("已修改步骤 #" editingIndex " · " s.name, "info")
    } else {
        steps.Push(s)
        selectedIndex := steps.Length
        Log("已添加步骤 #" selectedIndex " · " s.name, "info")
    }

    SaveConfig()
    RebuildList()
    if IsObject(ocrMouseGui)
        ocrMouseGui.Hide()
    if IsObject(ocrSettingsGui)
        ocrSettingsGui.Hide()
    editorGui.Hide()
    editorOpen := false
    mainGui.Show()
    WinActivate mainGui
    UpdateButtons()
}

CollectEditor() {
    global typeDDL, nameEdit, xEdit, yEdit, wEdit, hEdit
    global conditionModeDDL, exprEdit, countModeDDL, countEdit
    global text1Edit, text2Edit, text3Edit, text4Edit
    global waitEdit, intervalEdit, metDDL, unmetDDL
    global ocrActionDDL, ocrLangDDL, ocrScaleDDL, ocrEnhanceDDL
    global ocrMouseXEdit, ocrMouseYEdit, ocrMouseClicksEdit, ocrMouseIntervalEdit, ocrMouseSpeedEdit
    global buttonDDL, clicksEdit, clickIntervalEdit, moveSpeedEdit, delayEdit, afterEdit

    t := TypeFromIndex(typeDDL.Value)
    s := NewStep(t)
    s.name := Trim(nameEdit.Value)
    s.after := RequireInt(afterEdit.Value, "执行后延迟", 0, 3600000)

    if (t = "Delay") {
        s.delay := RequireInt(delayEdit.Value, "延时", 0, 3600000)
        if (s.name = "" || RegExMatch(s.name, "^延时 \d+ ms$"))
            s.name := "延时 " s.delay " ms"
        return s
    }

    s.x := RequireInt(xEdit.Value, "X 坐标", -100000, 100000)
    s.y := RequireInt(yEdit.Value, "Y 坐标", -100000, 100000)
    ValidatePoint(s.x, s.y)

    if (t = "OCR") {
        s.w := RequireInt(wEdit.Value, "区域宽度", 2, 100000)
        s.h := RequireInt(hEdit.Value, "区域高度", 2, 100000)
        ValidateRegion(s.x, s.y, s.w, s.h)

        terms := [Trim(text1Edit.Value), Trim(text2Edit.Value), Trim(text3Edit.Value), Trim(text4Edit.Value)]
        s.text1 := terms[1]
        s.text2 := terms[2]
        s.text3 := terms[3]
        s.text4 := terms[4]
        if (s.text1 = "" && s.text2 = "" && s.text3 = "" && s.text4 = "")
            throw ValueError("OCR 步骤至少需要填写一个关键词（文字1-4）。")

        mode := conditionModeDDL.Value
        if (mode < 1 || mode > 4)
            mode := 1
        s.conditionMode := mode
        s.requiredCount := 1
        s.countMode := "atLeast"

        if (mode = 4) {
            s.requiredCount := RequireInt(countEdit.Value, "满足项数", 1, 4)
            s.countMode := (countModeDDL.Value = 2) ? "exactly" : "atLeast"
            filled := 0
            for t in terms {
                if (t != "")
                    filled++
            }
            if (s.requiredCount > filled)
                throw ValueError("已填写 " filled " 项，无法满足 " s.requiredCount " 项；请补充关键词或减少项数。")
            s.expression := ""
        } else {
            s.expression := (mode = 3) ? Trim(exprEdit.Value) : BuildSimpleExpression(mode, terms)
            if (s.expression = "")
                throw ValueError("条件表达式不能为空。")
            ValidateConditionExpression(s.expression, terms)
        }

        s.ocrLanguage := OcrLanguageFromIndex(ocrLangDDL.Value)
        s.ocrScale := ocrScaleDDL.Value
        s.ocrEnhance := OcrEnhanceFromIndex(ocrEnhanceDDL.Value)

        act := OcrActionFromIndex(ocrActionDDL.Value)
        s.mouseAction := act
        s.mouseX := s.x + s.w // 2
        s.mouseY := s.y + s.h // 2
        s.mouseClicks := 1
        s.mouseClickInterval := 80
        s.mouseMoveSpeed := 0
        if (act != "None") {
            s.mouseX := RequireInt(ocrMouseXEdit.Value, "鼠标 X 坐标", -100000, 100000)
            s.mouseY := RequireInt(ocrMouseYEdit.Value, "鼠标 Y 坐标", -100000, 100000)
            ValidatePoint(s.mouseX, s.mouseY)
            if (act = "Move") {
                s.mouseMoveSpeed := RequireInt(ocrMouseSpeedEdit.Value, "移动速度", 0, 100)
            } else {
                s.mouseClicks := RequireInt(ocrMouseClicksEdit.Value, "点击次数", 1, 100)
                s.mouseClickInterval := RequireInt(ocrMouseIntervalEdit.Value, "点击间隔", 0, 3600000)
            }
        }

        s.wait := RequireInt(waitEdit.Value, "最长等待", 0, 3600000)
        s.interval := RequireInt(intervalEdit.Value, "检测间隔", 10, 3600000)
        s.metAction := (metDDL.Value = 2) ? "stop" : "continue"
        s.unmetAction := (unmetDDL.Value = 2) ? "stop" : "continue"
        s.relation := (mode = 2) ? "AND" : "OR"
        s.fail := (s.unmetAction = "continue") ? "skip" : "stop"

        if (s.name = "" || RegExMatch(s.name, "^OCR：")) {
            first := (terms[1] != "" ? terms[1] : terms[2] != "" ? terms[2] : terms[3] != "" ? terms[3] : terms[4])
            s.name := "OCR：" first
        }
    } else {
        s.w := 0
        s.h := 0
        action := buttonDDL.Value
        s.button := (action = 3) ? "Move" : (action = 2) ? "Right" : "Left"
        if (s.button = "Move") {
            s.moveSpeed := RequireInt(moveSpeedEdit.Value, "移动速度", 0, 100)
            s.clicks := 1
            s.clickInterval := 80
            if (s.name = "" || RegExMatch(s.name, "^移动到 \(-?\d+,-?\d+\)$"))
                s.name := "移动到 (" s.x "," s.y ")"
        } else {
            s.clicks := RequireInt(clicksEdit.Value, "点击次数", 1, 100)
            s.clickInterval := RequireInt(clickIntervalEdit.Value, "点击间隔", 0, 3600000)
            s.moveSpeed := 0
            if (s.name = "" || RegExMatch(s.name, "^点击 \(-?\d+,-?\d+\)$"))
                s.name := "点击 (" s.x "," s.y ")"
        }
    }

    return s
}

NewStep(type) {
    vs := VirtualScreen()
    s := {
        type: type, name: "",
        x: 0, y: 0, w: 0, h: 0,
        text1: "", text2: "", text3: "", text4: "",
        conditionMode: 1, expression: "", requiredCount: 1, countMode: "atLeast",
        ocrLanguage: "auto", ocrScale: 1, ocrEnhance: "none",
        relation: "OR", wait: 0, interval: 250,
        metAction: "continue", unmetAction: "stop", fail: "stop",
        mouseAction: "None", mouseX: 0, mouseY: 0,
        mouseClicks: 1, mouseClickInterval: 80, mouseMoveSpeed: 0,
        keys: "", keyMode: "send", keyRepeats: 1, keyInterval: 100,
        button: "Left", clicks: 1, clickInterval: 80, moveSpeed: 0,
        delay: 1000, after: 300
    }

    if (type = "OCR") {
        s.x := vs.x + Round(vs.w * 0.25)
        s.y := vs.y + Round(vs.h * 0.25)
        s.w := Min(600, vs.w - 40)
        s.h := Min(220, vs.h - 40)
        s.mouseX := s.x + s.w // 2
        s.mouseY := s.y + s.h // 2
    } else if (type = "Click") {
        s.x := vs.x + Round(vs.w / 2)
        s.y := vs.y + Round(vs.h / 2)
    }
    return s
}

; ============================================================
;  Queue list actions
; ============================================================

RebuildList() {
    global lv, steps, selectedIndex

    lv.Delete()
    for i, s in steps
        lv.Add("", i, s.name, StepTypeLabel(s), StepSummary(s), s.after " ms")

    if (selectedIndex >= 1 && selectedIndex <= steps.Length)
        lv.Modify(selectedIndex, "Select Focus Vis")
    else
        selectedIndex := 0

    UpdateButtons()
}

LV_ItemSelect(ctrl, row, *) {
    global selectedIndex
    selectedIndex := row
    UpdateButtons()
}

LV_DoubleClick(ctrl, row, *) {
    global running, steps
    if (running || row < 1)
        return
    if (steps[row].type = "Keyboard")
        OpenKeyboardEditor(row)
    else
        OpenEditor(steps[row].type, row)
}

EditSelected() {
    global selectedIndex, steps
    if (selectedIndex < 1) {
        MsgBox("请先选择一个步骤。", "提示", "Iconi")
        return
    }
    if (steps[selectedIndex].type = "Keyboard")
        OpenKeyboardEditor(selectedIndex)
    else
        OpenEditor(steps[selectedIndex].type, selectedIndex)
}

CopySelected() {
    global steps, selectedIndex
    if (selectedIndex < 1) {
        MsgBox("请先选择一个步骤。", "提示", "Iconi")
        return
    }
    s := steps[selectedIndex].Clone()
    s.name .= "（副本）"
    steps.InsertAt(selectedIndex + 1, s)
    selectedIndex += 1
    SaveConfig()
    RebuildList()
    Log("已复制步骤 #" selectedIndex " · " s.name, "info")
}

DeleteSelected() {
    global steps, selectedIndex
    if (selectedIndex < 1) {
        MsgBox("请先选择一个步骤。", "提示", "Iconi")
        return
    }
    s := steps[selectedIndex]
    if (MsgBox("确定删除步骤 #" selectedIndex "「" s.name "」？", "删除步骤", "YesNo Icon?") != "Yes")
        return
    steps.RemoveAt(selectedIndex)
    if (selectedIndex > steps.Length)
        selectedIndex := steps.Length
    SaveConfig()
    RebuildList()
    Log("已删除步骤 · " s.name, "info")
}

MoveSelected(delta) {
    global steps, selectedIndex
    if (selectedIndex < 1)
        return
    target := selectedIndex + delta
    if (target < 1 || target > steps.Length)
        return
    tmp := steps[selectedIndex]
    steps[selectedIndex] := steps[target]
    steps[target] := tmp
    selectedIndex := target
    SaveConfig()
    RebuildList()
}

ClearQueue() {
    global steps, selectedIndex
    if (steps.Length = 0)
        return
    if (MsgBox("确定清空整个执行队列？此操作不可撤销。", "清空队列", "YesNo Icon?") != "Yes")
        return
    steps := []
    selectedIndex := 0
    SaveConfig()
    RebuildList()
    Log("执行队列已清空", "info")
}

StepSummary(s) {
    if (s.type = "OCR") {
        expr := GetStepExpression(s)
        waitText := (s.wait > 0) ? " · 等" s.wait "ms" : ""
        actionText := ""
        if (s.mouseAction = "Move")
            actionText := " · 移动(" s.mouseX "," s.mouseY ")"
        else if (s.mouseAction = "Left")
            actionText := " · 左键(" s.mouseX "," s.mouseY ")"
        else if (s.mouseAction = "Right")
            actionText := " · 右键(" s.mouseX "," s.mouseY ")"
        setText := ""
        if (s.ocrLanguage != "auto")
            setText .= " · " OcrLanguageLabel(s.ocrLanguage)
        if (s.ocrScale > 1)
            setText .= " · " s.ocrScale "x"
        if (s.ocrEnhance != "none")
            setText .= " · " OcrEnhanceLabel(s.ocrEnhance)
        return "区域(" s.x "," s.y "," s.w "," s.h ") · " expr waitText actionText setText
    }
    if (s.type = "Click") {
        if (s.button = "Move")
            return "移动到 (" s.x "," s.y ") · 速度 " s.moveSpeed
        return "(" s.x "," s.y ") " ButtonLabel(s.button) " ×" s.clicks
    }
    if (s.type = "Keyboard") {
        mode := (s.keyMode = "text") ? "文本" : "按键"
        return mode "：" PreviewText(s.keys, 30) " ×" s.keyRepeats
    }
    return s.delay " ms"
}

; ============================================================
;  Queue execution
; ============================================================

StartQueue(*) {
    global running, stopRequested, steps, loopEdit, editorOpen, keyboardOpen, pickerActive
    global startBtn, stopBtn, mainGui, minimizeCheck, gStopHotkey

    if (running)
        return
    if (pickerActive)
        return
    if (editorOpen || keyboardOpen) {
        MsgBox("请先关闭步骤编辑窗口。", "提示", "Iconi")
        return
    }
    if (steps.Length = 0) {
        MsgBox("执行队列为空，请先添加步骤。", "提示", "Iconi")
        return
    }

    loopCount := ParseLoopCount(true)
    if (loopCount = "")
        return

    running := true
    stopRequested := false
    UpdateButtons()
    SetStatus("运行中…")
    runStart := A_TickCount
    Log("开始执行 · 共 " steps.Length " 步 · 循环 " (loopCount = 0 ? "无限" : loopCount " 次"), "header")

    stoppedByUser := false
    conditionStopped := false
    failed := false
    minimizeForRun := minimizeCheck.Value
    if (minimizeForRun) {
        mainGui.Minimize()
        Log("窗口已最小化；按 " gStopHotkey " 可停止。", "muted")
        Sleep(450)
        if (stopRequested)
            stoppedByUser := true
    }

    try {
        iteration := 0
        while !stopRequested {
            iteration += 1
            if (loopCount > 0 && iteration > loopCount)
                break

            Log("第 " iteration (loopCount = 0 ? " 轮（无限）" : " / " loopCount " 轮"), "muted")

            for idx, s in steps {
                if stopRequested {
                    stoppedByUser := true
                    break
                }

                ShowCurrent(idx)
                result := ExecuteStep(s, idx)
                if (result != "continue") {
                    if (result = "stopped" || stopRequested)
                        stoppedByUser := true
                    else if (result = "condition_stop")
                        conditionStopped := true
                    else
                        failed := true
                    break 2
                }

                if (s.after > 0) {
                    if !InterruptibleSleep(s.after) {
                        stoppedByUser := true
                        break 2
                    }
                }
            }
        }
    } catch as e {
        if (stopRequested)
            stoppedByUser := true
        else {
            failed := true
            Log("运行错误 · " e.Message, "error")
            if (minimizeForRun) {
                mainGui.Restore()
                WinActivate mainGui
            }
            MsgBox("运行出错：`n" e.Message, "错误", "Icon!")
        }
    } finally {
        running := false
        stopRequested := false
        ClearHighlight()
        UpdateButtons()
        elapsed := A_TickCount - runStart
        elapsedText := (elapsed < 60000) ? (elapsed " ms") : (Round(elapsed / 1000, 1) " s")
        if (stoppedByUser) {
            Log("已手动停止 · 用时 " elapsedText, "warn")
            SetStatus("已停止")
        } else if (conditionStopped) {
            Log("按条件设置停止 · 用时 " elapsedText, "warn")
            SetStatus("按条件设置停止")
        } else if (failed) {
            Log("队列因步骤失败而停止 · 用时 " elapsedText, "error")
            SetStatus("步骤失败，队列已停止")
        } else {
            Log("队列执行完毕 · 用时 " elapsedText, "success")
            SetStatus("就绪")
        }
        if (minimizeForRun) {
            mainGui.Restore()
            WinActivate mainGui
        }
    }
}

StopQueue(*) {
    global running, stopRequested, pickerActive
    if (pickerActive) {
        CancelPicker()
        return
    }
    if (!running) {
        SetStatus("当前没有运行中的队列")
        return
    }
    if (!stopRequested) {
        stopRequested := true
        SetStatus("正在停止…")
        Log("正在停止，等待当前动作结束…", "warn")
    }
}

ParseLoopCount(showError := false) {
    global loopEdit
    txt := Trim(loopEdit.Value)
    if !IsIntegerText(txt) {
        if (showError)
            MsgBox("循环次数必须是 0 或正整数（0 表示无限循环）。", "循环次数无效", "Icon!")
        return ""
    }
    n := Integer(txt)
    if (n < 0) {
        if (showError)
            MsgBox("循环次数不能为负数（0 表示无限循环）。", "循环次数无效", "Icon!")
        return ""
    }
    return n
}

ExecuteStep(s, idx) {
    global stopRequested

    if (s.type = "Delay") {
        Log("步骤 " idx " · 延时 " s.delay " ms", "step")
        return InterruptibleSleep(s.delay) ? "continue" : "stopped"
    }

    if (s.type = "Click") {
        if (s.button = "Move") {
            Log("步骤 " idx " · 移动到 (" s.x "," s.y ") · 速度 " s.moveSpeed, "step")
            MouseMove(s.x, s.y, s.moveSpeed)
            return stopRequested ? "stopped" : "continue"
        }

        Log("步骤 " idx " · 点击 (" s.x "," s.y ") " ButtonLabel(s.button) " ×" s.clicks, "step")
        Loop s.clicks {
            if (stopRequested)
                return "stopped"
            MouseClick(s.button = "Right" ? "Right" : "Left", s.x, s.y, 1, 0)
            if (A_Index < s.clicks && s.clickInterval > 0) {
                if !InterruptibleSleep(s.clickInterval)
                    return "stopped"
            }
        }
        return "continue"
    }

    if (s.type = "Keyboard") {
        modeText := (s.keyMode = "text") ? "输入文本" : "发送按键"
        Log("步骤 " idx " · " modeText " · " PreviewText(s.keys, 60) " ×" s.keyRepeats, "step")
        Loop s.keyRepeats {
            if (stopRequested)
                return "stopped"
            if (s.keyMode = "text")
                SendText(s.keys)
            else
                Send(s.keys)
            if (A_Index < s.keyRepeats && s.keyInterval > 0) {
                if !InterruptibleSleep(s.keyInterval)
                    return "stopped"
            }
        }
        return "continue"
    }

    if (s.type = "OCR")
        return ExecuteOcrStep(s, idx)

    throw ValueError("未知步骤类型：" s.type)
}

ExecuteOcrStep(s, idx) {
    global stopRequested

    terms := StepTerms(s)
    expr := GetStepExpression(s)
    condMode := GetStepConditionMode(s)
    requiredCount := s.requiredCount
    if (requiredCount < 1 || requiredCount > 4)
        requiredCount := 1
    countMode := (s.countMode = "exactly") ? "exactly" : "atLeast"
    Log("步骤 " idx " · OCR 检测 · 区域(" s.x "," s.y "," s.w "," s.h ")", "step")
    Log("条件：" expr, "info")
    Log("识别设置：" OcrLanguageLabel(s.ocrLanguage) " · 放大 " s.ocrScale " 倍 · " OcrEnhanceLabel(s.ocrEnhance), "muted")
    if (s.wait > 0)
        Log("最长等待 " s.wait " ms · 检测间隔 " s.interval " ms", "muted")

    deadline := A_TickCount + s.wait
    attempt := 0
    firstMiss := false

    loop {
        if (stopRequested)
            return "stopped"

        attempt += 1
        try ocr := OCRRegion(s.x, s.y, s.w, s.h, s.ocrLanguage, s.ocrScale, s.ocrEnhance)
        catch as e {
            if (stopRequested)
                return "stopped"
            throw Error("OCR 调用失败：" e.Message)
        }
        text := ocr.text

        ev := EvaluateOcrCondition(text, terms, expr, condMode, requiredCount, countMode)
        if (ev.ok) {
            Log("命中（第 " attempt " 次，" ocr.elapsed " ms）· " PreviewText(text), "success")
            if (s.mouseAction != "None") {
                actionResult := ExecuteOcrMouseAction(s, idx)
                if (actionResult != "continue")
                    return actionResult
            }
            if (s.metAction = "stop") {
                Log("条件已满足 → 按设置停止队列", "warn")
                return "condition_stop"
            }
            return "continue"
        }

        timedOut := (s.wait <= 0) || (A_TickCount >= deadline)
        if (timedOut) {
            Log("未满足条件 · " PreviewText(text), "warn")
            if (s.unmetAction = "stop") {
                Log("条件未满足 → 按设置停止队列", "error")
                return "condition_stop"
            }
            Log("条件未满足 → 按设置继续下一步", "warn")
            return "continue"
        }

        if (!firstMiss) {
            firstMiss := true
            Log("暂未满足，继续等待…", "muted")
        }

        remaining := deadline - A_TickCount
        if (remaining <= 0)
            continue
        if !InterruptibleSleep(Min(s.interval, remaining))
            return "stopped"
    }
}

ExecuteOcrMouseAction(s, idx) {
    global stopRequested

    if (s.mouseAction = "Move") {
        Log("  满足后 · 移动到 (" s.mouseX "," s.mouseY ") · 速度 " s.mouseMoveSpeed, "step")
        MouseMove(s.mouseX, s.mouseY, s.mouseMoveSpeed)
        return stopRequested ? "stopped" : "continue"
    }

    Log("  满足后 · " ButtonLabel(s.mouseAction) " (" s.mouseX "," s.mouseY ") ×" s.mouseClicks, "step")
    Loop s.mouseClicks {
        if (stopRequested)
            return "stopped"
        MouseClick(s.mouseAction = "Right" ? "Right" : "Left", s.mouseX, s.mouseY, 1, 0)
        if (A_Index < s.mouseClicks && s.mouseClickInterval > 0) {
            if !InterruptibleSleep(s.mouseClickInterval)
                return "stopped"
        }
    }
    return "continue"
}

ShowCurrent(idx) {
    global lv
    if (idx >= 1 && idx <= lv.GetCount())
        lv.Modify(idx, "Select Focus Vis")
    Sleep(1)
}

ClearHighlight() {
    global lv
    if (lv.GetCount() > 0)
        lv.Modify(0, "-Select -Focus")
}

InterruptibleSleep(ms) {
    global stopRequested
    if (ms <= 0)
        return !stopRequested
    end := A_TickCount + ms
    while (A_TickCount < end) {
        if (stopRequested)
            return false
        remain := end - A_TickCount
        Sleep(Min(25, remain))
    }
    return !stopRequested
}

; ============================================================
;  OCR matching / server
; ============================================================

StepTerms(s) {
    return [Trim(s.text1), Trim(s.text2), Trim(s.text3), Trim(s.text4)]
}

GetStepConditionMode(s) {
    mode := s.conditionMode
    if (mode >= 1 && mode <= 4)
        return mode
    if (Trim(s.expression) != "")
        return 3
    return (s.relation = "AND") ? 2 : 1
}

GetStepExpression(s) {
    mode := GetStepConditionMode(s)
    if (mode = 4) {
        count := s.requiredCount
        if (count < 1 || count > 4)
            count := 1
        return (s.countMode = "exactly" ? "恰好" : "至少") count " 项"
    }
    if (mode != 3)
        return BuildSimpleExpression(mode, StepTerms(s))
    return Trim(s.expression)
}

BuildSimpleExpression(mode, terms) {
    parts := []
    for i, t in terms {
        if (Trim(t) != "")
            parts.Push(i)
    }
    if (parts.Length = 0)
        return ""
    sep := (mode = 2) ? " 且 " : " 或 "
    return JoinArray(parts, sep)
}

ValidateConditionExpression(expr, terms) {
    global condRefs

    if (Trim(expr) = "")
        throw ValueError("条件表达式不能为空。")
    EvaluateCondition(expr, [false, false, false, false, false])
    for i in condRefs {
        if (Trim(terms[i]) = "")
            throw ValueError("表达式引用了未填写的文字" i "。")
    }
    return true
}

EvaluateOcrCondition(text, terms, expr, mode := 1, requiredCount := 1, countMode := "atLeast") {
    hay := NormalizeMatchText(text)
    found := [false, false, false, false, false]
    hits := []
    for i, t in terms {
        if (Trim(t) = "")
            continue
        if InStr(hay, NormalizeMatchText(t), false) {
            found[i] := true
            hits.Push(t)
        }
    }

    if (mode = 4) {
        ok := (countMode = "exactly") ? (hits.Length = requiredCount) : (hits.Length >= requiredCount)
    } else {
        ok := EvaluateCondition(expr, found)
    }
    return {ok: ok, hits: hits, found: found}
}

EvaluateCondition(expr, found) {
    global condExpr, condPos, condRefs

    condExpr := Trim(expr)
    condPos := 1
    condRefs := []
    if (condExpr = "")
        throw ValueError("条件表达式不能为空。")

    value := CondParseOr(found)
    CondSkipSpace()
    if (condPos <= StrLen(condExpr))
        throw ValueError("表达式无法解析，位置 " condPos "：“" SubStr(condExpr, condPos) "”")

    return value ? true : false
}

CondParseOr(found) {
    value := CondParseAnd(found)
    loop {
        CondSkipSpace()
        if !CondMatchOr()
            break
        rhs := CondParseAnd(found)
        value := value || rhs
    }
    return value
}

CondParseAnd(found) {
    value := CondParseFactor(found)
    loop {
        CondSkipSpace()
        if !CondMatchAnd()
            break
        rhs := CondParseFactor(found)
        value := value && rhs
    }
    return value
}

CondParseFactor(found) {
    global condExpr, condPos, condRefs

    CondSkipSpace()
    if (condPos > StrLen(condExpr))
        throw ValueError("条件表达式不完整。")

    ch := SubStr(condExpr, condPos, 1)
    if (ch = "(" || ch = "（") {
        condPos++
        value := CondParseOr(found)
        CondSkipSpace()
        close := SubStr(condExpr, condPos, 1)
        if (close != ")" && close != "）")
            throw ValueError("缺少右括号。")
        condPos++
        return value
    }

    if (ch ~= "^\d$") {
        n := Integer(ch)
        if (n < 1 || n > 4)
            throw ValueError("只能引用文字1-4，不能使用 " n "。")
        condPos++
        condRefs.Push(n)
        return found[n]
    }

    throw ValueError("无法识别“" ch "”。表达式只能使用 1-4、且/或、括号。")
}

CondMatchOr() {
    global condExpr, condPos

    if (condPos > StrLen(condExpr))
        return false
    if (SubStr(condExpr, condPos, 1) = "或") {
        condPos++
        return true
    }
    if (SubStr(condExpr, condPos, 2) = "||") {
        condPos += 2
        return true
    }
    if (SubStr(condExpr, condPos, 1) = "|") {
        condPos++
        return true
    }
    if (SubStr(condExpr, condPos, 2) ~= "i)^or$") {
        condPos += 2
        return true
    }
    return false
}

CondMatchAnd() {
    global condExpr, condPos

    if (condPos > StrLen(condExpr))
        return false
    if (SubStr(condExpr, condPos, 1) = "且") {
        condPos++
        return true
    }
    if (SubStr(condExpr, condPos, 2) = "&&") {
        condPos += 2
        return true
    }
    if (SubStr(condExpr, condPos, 3) ~= "i)^and$") {
        condPos += 3
        return true
    }
    if (SubStr(condExpr, condPos, 1) = "&") {
        condPos++
        return true
    }
    return false
}

CondSkipSpace() {
    global condExpr, condPos

    len := StrLen(condExpr)
    while (condPos <= len) {
        ch := SubStr(condExpr, condPos, 1)
        if (ch = " " || ch = "`t" || ch = "`r" || ch = "`n" || ch = "　")
            condPos++
        else
            break
    }
}

NormalizeMatchText(s) {
    s := StrReplace(s, Chr(0x3000), "")
    return RegExReplace(s, "\s+", "")
}

PreviewText(text, maxLen := 180) {
    t := Trim(RegExReplace(text, "\s+", " "))
    if (t = "")
        return "（未识别到文字）"
    return StrLen(t) > maxLen ? SubStr(t, 1, maxLen) "…" : t
}

StartOcrServer() {
    global SERVER_SCRIPT, serverPid, serverDir, serverReady, serverLang, serverStarting, serverFatal

    if !FileExist(SERVER_SCRIPT) {
        serverFatal := "找不到 ocr-server.ps1"
        UpdateServerStatus()
        return
    }

    if (serverPid && ProcessExist(serverPid))
        return

    serverReady := false
    serverLang := ""
    serverFatal := ""
    serverStarting := true
    serverDir := A_Temp "\AHK_OCR_Queue_" DllCall("GetCurrentProcessId")
    try DirCreate(serverDir)
    try {
        Loop Files, serverDir "\*.*", "F"
            FileDelete(A_LoopFilePath)
    }

    ps := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    if !FileExist(ps) {
        serverFatal := "找不到 Windows PowerShell"
        serverStarting := false
        UpdateServerStatus()
        return
    }

    parentPid := DllCall("GetCurrentProcessId")
    cmd := '"' ps '" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' SERVER_SCRIPT '" -Dir "' serverDir '" -ParentPid ' parentPid
    try {
        Run(cmd, A_ScriptDir, "Hide", &pid)
        serverPid := pid
    } catch as e {
        serverFatal := "无法启动 OCR 服务：" e.Message
        serverStarting := false
        UpdateServerStatus()
        return
    }

    UpdateServerStatus()
}

EnsureServer() {
    global serverReady, serverPid, serverDir, serverStarting

    if (serverReady && serverPid && ProcessExist(serverPid))
        return

    StartOcrServer()
    deadline := A_TickCount + 10000
    while (A_TickCount < deadline) {
        if CheckOcrServer(false)
            return
        if !ProcessExist(serverPid) {
            Sleep(100)
            if !ProcessExist(serverPid)
                throw Error("OCR 服务已退出，请检查 ocr-server.ps1 是否存在且可运行。")
        }
        Sleep(50)
    }
    throw Error("OCR 服务启动超时。")
}

CheckOcrServer(update := true) {
    global serverReady, serverPid, serverDir, serverLang, serverFatal, serverStarting

    if (serverDir = "")
        return false

    readyPath := serverDir "\ready.flag"
    fatalPath := serverDir "\fatal.flag"

    if (FileExist(readyPath)) {
        if (serverPid && !ProcessExist(serverPid)) {
            serverReady := false
            serverFatal := "OCR 服务进程已退出"
            if (update)
                UpdateServerStatus()
            return false
        }
        try {
            raw := FileRead(readyPath, "UTF-8")
            parts := StrSplit(raw, Chr(31),, 2)
            serverLang := (parts.Length >= 2) ? parts[2] : ""
        } catch {
            serverLang := ""
        }
        serverReady := true
        serverStarting := false
        serverFatal := ""
        if (update)
            UpdateServerStatus()
        return true
    }

    if (FileExist(fatalPath)) {
        try serverFatal := Trim(FileRead(fatalPath, "UTF-8"))
        catch
            serverFatal := "OCR 服务初始化失败"
        serverReady := false
        serverStarting := false
        if (update)
            UpdateServerStatus()
        return false
    }

    if (serverPid && !ProcessExist(serverPid)) {
        serverReady := false
        serverStarting := false
        if (serverFatal = "")
            serverFatal := "OCR 服务进程已退出"
        if (update)
            UpdateServerStatus()
        return false
    }

    if (update)
        UpdateServerStatus()
    return false
}

UpdateServerStatus() {
    global serverText, serverReady, serverLang, serverFatal, serverStarting

    if (serverReady) {
        serverText.Text := "OCR：就绪" (serverLang != "" ? " · " serverLang : "")
        serverText.SetFont("c1B7F3A")
        return
    }
    if (serverFatal != "") {
        msg := serverFatal
        if (StrLen(msg) > 70)
            msg := SubStr(msg, 1, 70) "…"
        serverText.Text := "OCR：不可用 — " msg
        serverText.SetFont("cD93025")
        return
    }
    if (serverStarting) {
        serverText.Text := "OCR：正在启动…"
        serverText.SetFont("c8A6D3B")
        return
    }
    serverText.Text := "OCR：未启动"
    serverText.SetFont("c8A6D3B")
}

OCRRegion(x, y, w, h, language := "auto", scale := 1, enhance := "none") {
    global serverDir, stopRequested

    EnsureServer()

    id := A_TickCount "-" Random(100000, 999999)
    reqPath := serverDir "\" id ".req"
    tmpPath := reqPath ".tmp"
    resPath := serverDir "\" id ".res"

    try FileDelete(tmpPath)
    FileAppend(x "|" y "|" w "|" h "|" language "|" scale "|" enhance, tmpPath, "UTF-8")
    FileMove(tmpPath, reqPath, true)

    deadline := A_TickCount + 15000
    while !FileExist(resPath) {
        if (stopRequested) {
            try FileDelete(reqPath)
            throw Error("已停止")
        }
        if (A_TickCount > deadline) {
            try FileDelete(reqPath)
            throw Error("OCR 请求超时（15 秒）")
        }
        Sleep(20)
    }

    raw := FileRead(resPath, "UTF-8")
    try FileDelete(resPath)

    parts := StrSplit(raw, Chr(31),, 3)
    if (parts.Length < 3)
        throw Error("OCR 服务返回了无效数据")

    if (parts[1] = "OK") {
        return {text: parts[3], elapsed: Integer(parts[2])}
    }
    throw Error(parts[3])
}

StopOcrServer() {
    global serverDir, serverPid, serverReady, serverStarting, serverFatal

    if (serverDir = "")
        return

    try FileAppend("1", serverDir "\stop.flag", "UTF-8")
    if (serverPid && ProcessExist(serverPid)) {
        try {
            if !ProcessWaitClose(serverPid, 2000)
                ProcessClose(serverPid)
        } catch {
            try ProcessClose(serverPid)
        }
    }
    try DirDelete(serverDir, true)
    serverPid := 0
    serverDir := ""
    serverReady := false
    serverStarting := false
    serverFatal := ""
}

; ============================================================
;  Coordinate / region picker
; ============================================================

PickPoint(*) {
    global editorOpen, editorGui
    if (!editorOpen)
        return
    StartPicker("point", editorGui)
}

PickRegion(*) {
    global editorOpen, editorGui
    if (!editorOpen)
        return
    StartPicker("region", editorGui)
}

StartPicker(mode, parent, target := "editor") {
    global pickerActive, pickerMode, pickerParent, pickerArmed, pickerDragging
    global pickerOverlay, pickerHint, pickerPointDown, pickerTarget

    if (pickerActive)
        return

    EnsurePicker()
    pickerActive := true
    pickerMode := mode
    pickerParent := parent
    pickerTarget := target
    pickerArmed := !GetKeyState("LButton", "P")
    pickerDragging := false
    pickerPointDown := false

    vs := VirtualScreen()
    pickerOverlay.Show("NoActivate x" vs.x " y" vs.y " w" vs.w " h" vs.h)
    WinSetTransparent(120, pickerOverlay)
    pickerHint.Move(0, 50, vs.w, 44)
    pickerHint.Text := (mode = "point")
        ? "单击目标位置    ·    右键 / Esc 取消"
        : "按住左键拖动框选 OCR 区域    ·    右键 / Esc 取消"

    parent.Hide()
    ToolTip(mode = "point" ? "请单击目标位置" : "请按住左键拖动框选区域",
        A_ScreenWidth // 2, 30, 19)

    try Hotkey("Esc", PickerEsc, "On")
    SetTimer(PickerTick, 15)
}

EnsurePicker() {
    global pickerOverlay, pickerHint, pickerBorders

    if IsObject(pickerOverlay)
        return

    pickerOverlay := Gui("-DPIScale +AlwaysOnTop -Caption +ToolWindow +E0x08000000")
    pickerOverlay.BackColor := "101820"
    pickerOverlay.SetFont("s18 Bold cWhite", "Microsoft YaHei UI")
    pickerHint := pickerOverlay.AddText("x0 y50 w800 h44 Center BackgroundTrans +E0x20", "")

    pickerBorders := []
    Loop 4 {
        g := Gui("-DPIScale +AlwaysOnTop -Caption +ToolWindow +E0x08000000 +E0x20")
        g.BackColor := "FF3B30"
        g.Show("NoActivate x-10000 y-10000 w1 h1")
        pickerBorders.Push(g)
    }

    OnMessage(0x0201, Picker_WMLButtonDown)
    OnMessage(0x0202, Picker_WMLButtonUp)
    OnMessage(0x0204, Picker_WMRButtonDown)
}

Picker_WMLButtonDown(wParam, lParam, msg, hwnd) {
    global pickerActive, pickerOverlay
    if (!pickerActive || !IsObject(pickerOverlay))
        return
    if !IsPickerWindow(hwnd)
        return
    PickerLButtonDown()
}

Picker_WMLButtonUp(wParam, lParam, msg, hwnd) {
    global pickerActive, pickerOverlay
    if (!pickerActive || !IsObject(pickerOverlay))
        return
    if !IsPickerWindow(hwnd)
        return
    PickerLButtonUp()
}

Picker_WMRButtonDown(wParam, lParam, msg, hwnd) {
    global pickerActive, pickerOverlay
    if (!pickerActive || !IsObject(pickerOverlay))
        return
    if !IsPickerWindow(hwnd)
        return
    CancelPicker()
}

IsPickerWindow(hwnd) {
    global pickerOverlay
    if !IsObject(pickerOverlay)
        return false
    root := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
    return root = pickerOverlay.Hwnd
}

PickerTick() {
    global pickerActive, pickerArmed

    if (!pickerActive)
        return

    MouseGetPos(&mx, &my)

    if (!pickerArmed && !GetKeyState("LButton", "P"))
        pickerArmed := true

    if (!pickerArmed) {
        ToolTip("请先松开鼠标", mx + 20, my + 20, 19)
        return
    }

    PickerTickFallback(mx, my)
}

PickerLButtonDown(*) {
    global pickerActive, pickerArmed, pickerMode, pickerDragging
    global pickerStartX, pickerStartY, pickerPointDown, pickerPointX, pickerPointY

    if (!pickerActive || !pickerArmed)
        return

    MouseGetPos(&mx, &my)
    if (pickerMode = "point") {
        pickerPointDown := true
        pickerPointX := mx
        pickerPointY := my
        ToolTip("X: " mx "    Y: " my "`n松开左键确认    ·    右键 / Esc 取消", mx + 20, my + 20, 19)
        return
    }

    pickerDragging := true
    pickerStartX := mx
    pickerStartY := my
    UpdateBorders(mx, my, 3, 3)
}

PickerLButtonUp(*) {
    global pickerActive, pickerArmed, pickerMode, pickerDragging
    global pickerStartX, pickerStartY, pickerPointDown, pickerPointX, pickerPointY

    if (!pickerActive)
        return

    if (!pickerArmed) {
        pickerArmed := true
        return
    }

    MouseGetPos(&mx, &my)

    if (pickerMode = "point") {
        if (!pickerPointDown)
            return
        pickerPointDown := false
        FinishPicker(pickerPointX, pickerPointY, 0, 0)
        return
    }

    if (!pickerDragging)
        return

    pickerDragging := false
    HideBorders()
    x1 := Min(pickerStartX, mx)
    y1 := Min(pickerStartY, my)
    w := Abs(mx - pickerStartX)
    h := Abs(my - pickerStartY)
    if (w < 4 || h < 4) {
        ToolTip("区域太小，请重新拖动框选", mx + 20, my + 20, 19)
        return
    }
    FinishPicker(x1, y1, w, h)
}

PickerTickFallback(mx, my) {
    global pickerMode, pickerDragging, pickerStartX, pickerStartY
    global pickerPointDown, pickerPointX, pickerPointY

    if GetKeyState("RButton", "P") {
        CancelPicker()
        return
    }

    if (pickerMode = "point") {
        if GetKeyState("LButton", "P") {
            if (!pickerPointDown) {
                pickerPointDown := true
                pickerPointX := mx
                pickerPointY := my
            }
            ToolTip("X: " pickerPointX "    Y: " pickerPointY "`n松开左键确认    ·    右键 / Esc 取消",
                mx + 20, my + 20, 19)
        } else {
            if (pickerPointDown) {
                FinishPicker(pickerPointX, pickerPointY, 0, 0)
                return
            }
            ToolTip("X: " mx "    Y: " my "`n单击目标位置    ·    右键 / Esc 取消", mx + 20, my + 20, 19)
        }
        return
    }

    if GetKeyState("LButton", "P") {
        if (!pickerDragging) {
            pickerDragging := true
            pickerStartX := mx
            pickerStartY := my
        }
        x1 := Min(pickerStartX, mx)
        y1 := Min(pickerStartY, my)
        w := Abs(mx - pickerStartX)
        h := Abs(my - pickerStartY)
        UpdateBorders(x1, y1, w, h)
        ToolTip("区域: " x1 ", " y1 "    " w " × " h "`n松开左键确认    ·    右键 / Esc 取消",
            mx + 20, my + 20, 19)
        return
    }

    if (pickerDragging) {
        x1 := Min(pickerStartX, mx)
        y1 := Min(pickerStartY, my)
        w := Abs(mx - pickerStartX)
        h := Abs(my - pickerStartY)
        if (w < 4 || h < 4) {
            pickerDragging := false
            HideBorders()
            ToolTip("区域太小，请重新拖动框选", mx + 20, my + 20, 19)
        } else {
            FinishPicker(x1, y1, w, h)
        }
        return
    }

    ToolTip("按住左键拖动框选区域`n右键 / Esc 取消", mx + 20, my + 20, 19)
}

UpdateBorders(x, y, w, h) {
    global pickerBorders
    if (w < 3)
        w := 3
    if (h < 3)
        h := 3
    t := 3
    pickerBorders[1].Move(x, y, w, t)
    pickerBorders[2].Move(x, y + h - t, w, t)
    pickerBorders[3].Move(x, y, t, h)
    pickerBorders[4].Move(x + w - t, y, t, h)
}

HideBorders() {
    global pickerBorders
    for g in pickerBorders
        g.Move(-10000, -10000, 1, 1)
}

FinishPicker(x, y, w, h) {
    global pickerMode, pickerTarget, pickerActive, xEdit, yEdit, wEdit, hEdit
    global ocrMouseXEdit, ocrMouseYEdit

    mode := pickerMode
    target := pickerTarget
    EndPicker()

    if (target = "ocrMouse") {
        ocrMouseXEdit.Value := x
        ocrMouseYEdit.Value := y
        UpdateOcrMouseUI()
        Log("已拾取鼠标目标 · (" x "," y ")", "info")
        return
    }

    if (mode = "point") {
        xEdit.Value := x
        yEdit.Value := y
        Log("已拾取坐标 · (" x "," y ")", "info")
    } else {
        xEdit.Value := x
        yEdit.Value := y
        wEdit.Value := w
        hEdit.Value := h
        Log("已拾取区域 · (" x "," y "," w " × " h ")", "info")
    }
}

CancelPicker() {
    global pickerActive
    if (!pickerActive)
        return
    EndPicker()
    Log("已取消拾取", "muted")
}

EndPicker() {
    global pickerActive, pickerParent, pickerMode, pickerDragging, pickerTarget
    global pickerOverlay, pickerPointDown

    SetTimer(PickerTick, 0)
    try Hotkey("Esc", "Off")
    ToolTip("", , , 19)
    ToolTip()
    HideBorders()
    pickerOverlay.Hide()
    pickerActive := false
    pickerDragging := false
    pickerPointDown := false

    parent := pickerParent
    pickerParent := ""
    pickerMode := ""
    pickerTarget := ""
    if IsObject(parent) {
        parent.Show()
        WinActivate parent.Hwnd
    }
}

PickerEsc(*) {
    CancelPicker()
}

; ============================================================
;  Test OCR
; ============================================================

TestOcr(*) {
    global editorGui, mainGui, xEdit, yEdit, wEdit, hEdit

    try {
        x := RequireInt(xEdit.Value, "X 坐标", -100000, 100000)
        y := RequireInt(yEdit.Value, "Y 坐标", -100000, 100000)
        w := RequireInt(wEdit.Value, "区域宽度", 2, 100000)
        h := RequireInt(hEdit.Value, "区域高度", 2, 100000)
        ValidateRegion(x, y, w, h)
        cond := GetEditorCondition()
        settings := GetEditorOcrSettings()
    } catch as e {
        MsgBox(e.Message, "测试 OCR", "Icon!")
        return
    }

    editorGui.Hide()
    mainGui.Hide()
    Sleep(250)

    result := ""
    err := ""
    try {
        result := OCRRegion(x, y, w, h, settings.language, settings.scale, settings.enhance)
    } catch as e {
        err := e.Message
    }

    mainGui.Show("NoActivate")
    editorGui.Show()
    WinActivate editorGui

    if (err != "") {
        MsgBox("OCR 测试失败：`n" err, "测试 OCR", "Icon!")
        return
    }

    text := result.text
    shown := Trim(RegExReplace(text, "\s+", " "))
    if (shown = "")
        shown := "（没有识别到文字）"
    if (StrLen(shown) > 1600)
        shown := SubStr(shown, 1, 1600) "…"

    ev := EvaluateOcrCondition(text, cond.terms, cond.expression, cond.mode, cond.requiredCount, cond.countMode)
    status := ""
    for i, t in cond.terms {
        if (Trim(t) != "")
            status .= "文字" i (ev.found[i] ? " ✓  " : " ✗  ")
    }

    msg := "区域：(" x "," y "," w "," h ")`n耗时：" result.elapsed " ms"
    msg .= "`n识别：" OcrLanguageLabel(settings.language) " · 放大 " settings.scale " 倍 · " OcrEnhanceLabel(settings.enhance)
    msg .= "`n`n条件：`n" cond.expression
    msg .= "`n`n各文字命中：" (status = "" ? "无" : status)
    msg .= "`n命中项数：" ev.hits.Length
    msg .= "`n结果：" (ev.ok ? "满足 ✔" : "不满足 ✘")
    msg .= "`n`n识别文本：`n" shown

    Log("OCR 测试 · (" x "," y "," w "," h ") · " (ev.ok ? "满足" : "不满足"), ev.ok ? "success" : "warn")
    MsgBox(msg, "测试 OCR")
}

GetEditorCondition() {
    global typeDDL, conditionModeDDL, exprEdit, countModeDDL, countEdit
    global text1Edit, text2Edit, text3Edit, text4Edit

    if (TypeFromIndex(typeDDL.Value) != "OCR")
        throw ValueError("当前步骤不是 OCR 类型。")

    terms := [Trim(text1Edit.Value), Trim(text2Edit.Value), Trim(text3Edit.Value), Trim(text4Edit.Value)]
    if (terms[1] = "" && terms[2] = "" && terms[3] = "" && terms[4] = "")
        throw ValueError("请至少填写一个关键词（文字1-4）。")

    mode := conditionModeDDL.Value
    if (mode < 1 || mode > 4)
        mode := 1

    if (mode = 4) {
        required := RequireInt(countEdit.Value, "满足项数", 1, 4)
        countMode := (countModeDDL.Value = 2) ? "exactly" : "atLeast"
        filled := 0
        for t in terms {
            if (t != "")
                filled++
        }
        if (required > filled)
            throw ValueError("已填写 " filled " 项，无法满足 " required " 项；请补充关键词或减少项数。")
        expr := (countMode = "exactly" ? "恰好" : "至少") required " 项"
        return {mode: mode, expression: expr, terms: terms, requiredCount: required, countMode: countMode}
    }

    expr := (mode = 3) ? Trim(exprEdit.Value) : BuildSimpleExpression(mode, terms)
    if (expr = "")
        throw ValueError("条件表达式不能为空。")
    ValidateConditionExpression(expr, terms)
    return {mode: mode, expression: expr, terms: terms, requiredCount: 1, countMode: "atLeast"}
}

; ============================================================
;  Hotkeys / config / UI state
; ============================================================

RegisterInitialHotkeys() {
    global gStartHotkey, gStopHotkey, startHkEdit, stopHkEdit

    if (Trim(startHkEdit.Value) = "")
        startHkEdit.Value := "F9"
    if (Trim(stopHkEdit.Value) = "")
        stopHkEdit.Value := "F10"

    try {
        ApplyHotkeys(false)
    } catch as e {
        gStartHotkey := "F9"
        gStopHotkey := "F10"
        startHkEdit.Value := gStartHotkey
        stopHkEdit.Value := gStopHotkey
        try ApplyHotkeys(false)
        Log("自定义快捷键无效（" e.Message "），已改用 F9 / F10", "warn")
    }
}

ApplyHotkeys_UI(*) {
    global gStartHotkey, gStopHotkey, startHkEdit, stopHkEdit
    try {
        ApplyHotkeys(true)
        Log("快捷键已更新 · " gStartHotkey " 开始 / " gStopHotkey " 停止", "success")
        SetStatus("快捷键已更新")
    } catch as e {
        startHkEdit.Value := gStartHotkey
        stopHkEdit.Value := gStopHotkey
        MsgBox(e.Message, "快捷键无效", "Icon!")
    }
}

ApplyHotkeys(save := true) {
    global gStartHotkey, gStopHotkey, startHkEdit, stopHkEdit

    newStart := Trim(startHkEdit.Value)
    newStop := Trim(stopHkEdit.Value)
    if (newStart = "" || newStop = "")
        throw ValueError("开始和停止快捷键都不能为空。")
    if (newStart = newStop)
        throw ValueError("开始和停止快捷键不能相同。")

    oldStart := gStartHotkey
    oldStop := gStopHotkey

    ; Clear old bindings first so the new pair can safely swap keys.
    try {
        if (oldStart != "")
            Hotkey(oldStart, "Off")
    }
    try {
        if (oldStop != "" && oldStop != oldStart)
            Hotkey(oldStop, "Off")
    }

    try {
        Hotkey(newStart, StartHotkeyHandler, "On")
        Hotkey(newStop, StopHotkeyHandler, "On")
    } catch as e {
        try Hotkey(newStart, "Off")
        try Hotkey(newStop, "Off")
        ; restore previous pair
        try {
            Hotkey(oldStart, StartHotkeyHandler, "On")
            Hotkey(oldStop, StopHotkeyHandler, "On")
        }
        throw ValueError("无效的快捷键（" e.Message "）。示例：F9、^F9、!s、#c")
    }

    gStartHotkey := newStart
    gStopHotkey := newStop
    UpdateHotkeyLabels()
    if (save)
        SaveConfig()
}

StartHotkeyHandler(*) {
    global pickerActive, editorOpen, keyboardOpen, running
    if (pickerActive)
        return
    if (editorOpen || keyboardOpen)
        return
    if (!running)
        StartQueue()
}

StopHotkeyHandler(*) {
    global pickerActive, running
    if (pickerActive) {
        CancelPicker()
        return
    }
    if (running)
        StopQueue()
}

UpdateHotkeyLabels() {
    global startBtn, stopBtn, gStartHotkey, gStopHotkey
    startBtn.Text := "▶ 开始 (" gStartHotkey ")"
    stopBtn.Text := "■ 停止 (" gStopHotkey ")"
}

UpdateButtons() {
    global running, selectedIndex, steps
    global addOcrBtn, addClickBtn, addKeyboardBtn, addDelayBtn, editBtn, delBtn, copyBtn
    global upBtn, downBtn, clearBtn, saveCfgBtn, loadCfgBtn
    global startBtn, stopBtn, loopEdit, startHkEdit, stopHkEdit, applyHkBtn, minimizeCheck

    hasSel := (selectedIndex >= 1 && selectedIndex <= steps.Length)

    addOcrBtn.Enabled := !running
    addClickBtn.Enabled := !running
    addKeyboardBtn.Enabled := !running
    addDelayBtn.Enabled := !running
    editBtn.Enabled := hasSel && !running
    copyBtn.Enabled := hasSel && !running
    delBtn.Enabled := hasSel && !running
    upBtn.Enabled := hasSel && !running
    downBtn.Enabled := hasSel && !running
    clearBtn.Enabled := !running && steps.Length > 0
    saveCfgBtn.Enabled := !running
    loadCfgBtn.Enabled := !running

    loopEdit.Enabled := !running
    startHkEdit.Enabled := !running
    stopHkEdit.Enabled := !running
    applyHkBtn.Enabled := !running
    minimizeCheck.Enabled := !running

    startBtn.Enabled := !running && steps.Length > 0
    stopBtn.Enabled := running

    UpdateHotkeyLabels()
}

SetStatus(txt) {
    global statusText
    statusText.Text := txt
}

InitRichLog() {
    global logEdit

    hwnd := logEdit.Hwnd
    SendMessage(0x0443, 0, 0x00FFFFFF, hwnd)       ; EM_SETBKGNDCOLOR
    SendMessage(0x00CF, 1, 0, hwnd)                ; EM_SETREADONLY
}

SetLogReadOnly(flag) {
    global logEdit
    SendMessage(0x00CF, flag ? 1 : 0, 0, logEdit.Hwnd)
}

AppendRichLog(text, color, bold := false) {
    global logEdit

    hwnd := logEdit.Hwnd
    SetLogReadOnly(false)
    len := SendMessage(0x000E, 0, 0, hwnd)
    SendMessage(0x00B1, len, len, hwnd)            ; EM_SETSEL to end

    fmt := Buffer(92, 0)
    NumPut("UInt", 92, fmt, 0)
    NumPut("UInt", 0x40000000 | (bold ? 0x00000001 : 0), fmt, 4) ; CFM_COLOR | CFM_BOLD
    NumPut("UInt", bold ? 0x00000001 : 0, fmt, 8)                ; CFE_BOLD
    NumPut("UInt", color, fmt, 20)
    SendMessage(0x0444, 1, fmt.Ptr, hwnd)          ; EM_SETCHARFORMAT SCF_SELECTION
    SendMessage(0x00C2, 0, StrPtr(text), hwnd)     ; EM_REPLACESEL
    SetLogReadOnly(true)
}

TrimRichLog() {
    global logEdit

    hwnd := logEdit.Hwnd
    lines := SendMessage(0x00BA, 0, 0, hwnd)       ; EM_GETLINECOUNT
    if (lines <= 400)
        return

    firstKept := lines - 400
    idx := SendMessage(0x00BB, firstKept, 0, hwnd) ; EM_LINEINDEX
    if (idx <= 0)
        return

    SetLogReadOnly(false)
    SendMessage(0x00B1, 0, idx, hwnd)
    SendMessage(0x00C2, 0, StrPtr(""), hwnd)
    SetLogReadOnly(true)
}

ScrollRichLog() {
    global logEdit

    hwnd := logEdit.Hwnd
    len := SendMessage(0x000E, 0, 0, hwnd)
    SendMessage(0x00B1, len, len, hwnd)
    SendMessage(0x00B7, 0, 0, hwnd)
}

Log(msg, level := "info") {
    global logEdit

    t := FormatTime(, "HH:mm:ss")
    switch level {
        case "header":
            len := SendMessage(0x000E, 0, 0, logEdit.Hwnd)
            line := (len > 0 ? "`r`n" : "") "[" t "] " msg "`r`n"
            color := 0x222222
            bold := true
        case "step":
            line := "[" t "] ▶ " msg "`r`n"
            color := 0xA85F1E
            bold := false
        case "success":
            line := "[" t "] ✓ " msg "`r`n"
            color := 0x327D2E
            bold := false
        case "warn":
            line := "[" t "] ! " msg "`r`n"
            color := 0x006AB2
            bold := false
        case "error":
            line := "[" t "] ✗ " msg "`r`n"
            color := 0x2828C6
            bold := false
        case "muted":
            line := "[" t "] ─ " msg "`r`n"
            color := 0x777777
            bold := false
        default:
            line := "[" t "] · " msg "`r`n"
            color := 0x444444
            bold := false
    }

    AppendRichLog(line, color, bold)
    TrimRichLog()
    ScrollRichLog()
}

ClearLog(*) {
    global logEdit
    SetLogReadOnly(false)
    SendMessage(0x000C, 0, 0, logEdit.Hwnd)
    SetLogReadOnly(true)
    SetStatus("日志已清空")
}

CopyLog(*) {
    global logEdit

    hwnd := logEdit.Hwnd
    len := SendMessage(0x000E, 0, 0, hwnd)
    if (len <= 0)
        return

    buf := Buffer((len + 1) * 2, 0)
    SendMessage(0x000D, len + 1, buf.Ptr, hwnd) ; WM_GETTEXT
    text := StrGet(buf, "UTF-16")
    if (text != "") {
        A_Clipboard := text
        SetStatus("日志已复制到剪贴板")
    }
}

SaveConfig_UI(*) {
    global CONFIG_FILE
    SaveConfig()
    Log("配置已保存 · " CONFIG_FILE, "info")
    SetStatus("配置已保存")
}

LoadConfig_UI(*) {
    global CONFIG_FILE, running, gStartHotkey, gStopHotkey, startHkEdit, stopHkEdit

    if (running) {
        MsgBox("请先停止队列。", "提示", "Iconi")
        return
    }
    file := FileSelect(1, A_ScriptDir, "选择配置文件", "配置文件 (*.ini)")
    if (file = "")
        return
    if !LoadSettings(file) {
        MsgBox("无法载入配置文件。", "载入失败", "Icon!")
        return
    }
    CONFIG_FILE := file
    try ApplyHotkeys(false)
    catch as e {
        startHkEdit.Value := gStartHotkey
        stopHkEdit.Value := gStopHotkey
        MsgBox("配置中的快捷键无效，已保留原快捷键。`n" e.Message, "快捷键", "Icon!")
    }
    RebuildList()
    Log("已载入配置 · " file, "info")
    SetStatus("配置已载入")
}

SaveConfig() {
    global CONFIG_FILE, steps, loopEdit, startHkEdit, stopHkEdit, gStartHotkey, gStopHotkey, minimizeCheck

    try {
        lc := Trim(loopEdit.Value)
        if (!IsIntegerText(lc) || Integer(lc) < 0)
            lc := 1

        IniWrite(lc, CONFIG_FILE, "App", "LoopCount")
        IniWrite(gStartHotkey, CONFIG_FILE, "App", "StartHotkey")
        IniWrite(gStopHotkey, CONFIG_FILE, "App", "StopHotkey")
        IniWrite(minimizeCheck.Value, CONFIG_FILE, "App", "MinimizeOnRun")
        IniWrite(steps.Length, CONFIG_FILE, "Queue", "Count")

        for i, s in steps {
            sec := "Step" i
            IniWrite(s.type, CONFIG_FILE, sec, "Type")
            IniWrite(s.name, CONFIG_FILE, sec, "Name")
            IniWrite(s.x, CONFIG_FILE, sec, "X")
            IniWrite(s.y, CONFIG_FILE, sec, "Y")
            IniWrite(s.w, CONFIG_FILE, sec, "W")
            IniWrite(s.h, CONFIG_FILE, sec, "H")
            IniWrite(s.text1, CONFIG_FILE, sec, "Text1")
            IniWrite(s.text2, CONFIG_FILE, sec, "Text2")
            IniWrite(s.text3, CONFIG_FILE, sec, "Text3")
            IniWrite(s.text4, CONFIG_FILE, sec, "Text4")
            IniWrite(s.conditionMode, CONFIG_FILE, sec, "ConditionMode")
            IniWrite(s.expression, CONFIG_FILE, sec, "Expression")
            IniWrite(s.requiredCount, CONFIG_FILE, sec, "RequiredCount")
            IniWrite(s.countMode, CONFIG_FILE, sec, "CountMode")
            IniWrite(s.ocrLanguage, CONFIG_FILE, sec, "OcrLanguage")
            IniWrite(s.ocrScale, CONFIG_FILE, sec, "OcrScale")
            IniWrite(s.ocrEnhance, CONFIG_FILE, sec, "OcrEnhance")
            IniWrite(s.relation, CONFIG_FILE, sec, "Relation")
            IniWrite(s.wait, CONFIG_FILE, sec, "Wait")
            IniWrite(s.interval, CONFIG_FILE, sec, "Interval")
            IniWrite(s.metAction, CONFIG_FILE, sec, "MetAction")
            IniWrite(s.unmetAction, CONFIG_FILE, sec, "UnmetAction")
            IniWrite(s.fail, CONFIG_FILE, sec, "Fail")
            IniWrite(s.mouseAction, CONFIG_FILE, sec, "MouseAction")
            IniWrite(s.mouseX, CONFIG_FILE, sec, "MouseX")
            IniWrite(s.mouseY, CONFIG_FILE, sec, "MouseY")
            IniWrite(s.mouseClicks, CONFIG_FILE, sec, "MouseClicks")
            IniWrite(s.mouseClickInterval, CONFIG_FILE, sec, "MouseClickInterval")
            IniWrite(s.mouseMoveSpeed, CONFIG_FILE, sec, "MouseMoveSpeed")
            IniWrite(s.button, CONFIG_FILE, sec, "Button")
            IniWrite(s.clicks, CONFIG_FILE, sec, "Clicks")
            IniWrite(s.clickInterval, CONFIG_FILE, sec, "ClickInterval")
            IniWrite(s.moveSpeed, CONFIG_FILE, sec, "MoveSpeed")
            IniWrite(s.keys, CONFIG_FILE, sec, "Keys")
            IniWrite(s.keyMode, CONFIG_FILE, sec, "KeyMode")
            IniWrite(s.keyRepeats, CONFIG_FILE, sec, "KeyRepeats")
            IniWrite(s.keyInterval, CONFIG_FILE, sec, "KeyInterval")
            IniWrite(s.delay, CONFIG_FILE, sec, "Delay")
            IniWrite(s.after, CONFIG_FILE, sec, "After")
        }

        ; Remove sections left over from a longer queue.
        Loop 200 {
            if (A_Index > steps.Length)
                IniDelete(CONFIG_FILE, "Step" A_Index)
        }
    } catch as e {
        Log("保存配置失败 · " e.Message, "error")
    }
}

LoadSettings(file) {
    global steps, selectedIndex, loopEdit, startHkEdit, stopHkEdit, minimizeCheck
    global gStartHotkey, gStopHotkey, CONFIG_FILE

    if !FileExist(file)
        return false

    try {
        lc := IniRead(file, "App", "LoopCount", "1")
        if (!IsIntegerText(lc) || Integer(lc) < 0)
            lc := 1
        loopEdit.Value := lc

        minimizeCheck.Value := (IniRead(file, "App", "MinimizeOnRun", "1") = "0") ? 0 : 1

        start := IniRead(file, "App", "StartHotkey", "F9")
        stop := IniRead(file, "App", "StopHotkey", "F10")
        if (Trim(start) = "")
            start := "F9"
        if (Trim(stop) = "")
            stop := "F10"
        startHkEdit.Value := start
        stopHkEdit.Value := stop

        count := IniRead(file, "Queue", "Count", "0")
        count := IsIntegerText(count) ? Integer(count) : 0
        if (count < 0)
            count := 0
        if (count > 200)
            count := 200

        newSteps := []
        Loop count {
            sec := "Step" A_Index
            t := IniRead(file, sec, "Type", "")
            if (t != "OCR" && t != "Click" && t != "Delay" && t != "Keyboard")
                continue
            s := NewStep(t)
            s.name := IniRead(file, sec, "Name", "")
            s.x := ReadIniInt(file, sec, "X", s.x)
            s.y := ReadIniInt(file, sec, "Y", s.y)
            s.w := ReadIniInt(file, sec, "W", s.w)
            s.h := ReadIniInt(file, sec, "H", s.h)
            s.text1 := IniRead(file, sec, "Text1", "")
            s.text2 := IniRead(file, sec, "Text2", "")
            s.text3 := IniRead(file, sec, "Text3", "")
            s.text4 := IniRead(file, sec, "Text4", "")

            oldRelation := (IniRead(file, sec, "Relation", "OR") = "AND") ? "AND" : "OR"
            oldFail := (IniRead(file, sec, "Fail", "stop") = "skip") ? "skip" : "stop"
            s.relation := oldRelation

            s.expression := IniRead(file, sec, "Expression", "")
            cm := IniRead(file, sec, "ConditionMode", "")
            if (cm = "1" || cm = "2" || cm = "3" || cm = "4")
                s.conditionMode := Integer(cm)
            else if (Trim(s.expression) != "")
                s.conditionMode := 3
            else
                s.conditionMode := (oldRelation = "AND") ? 2 : 1
            s.requiredCount := ReadIniInt(file, sec, "RequiredCount", 1)
            s.countMode := (IniRead(file, sec, "CountMode", "atLeast") = "exactly") ? "exactly" : "atLeast"
            ol := IniRead(file, sec, "OcrLanguage", "auto")
            s.ocrLanguage := (ol = "zh" || ol = "en" || ol = "mixed") ? ol : "auto"
            s.ocrScale := ReadIniInt(file, sec, "OcrScale", 1)
            if (s.ocrScale < 1 || s.ocrScale > 3)
                s.ocrScale := 1
            oe := IniRead(file, sec, "OcrEnhance", "none")
            s.ocrEnhance := (oe = "gray" || oe = "contrast") ? oe : "none"

            s.wait := ReadIniInt(file, sec, "Wait", 0)
            s.interval := ReadIniInt(file, sec, "Interval", 250)
            s.metAction := (IniRead(file, sec, "MetAction", "continue") = "stop") ? "stop" : "continue"
            ua := IniRead(file, sec, "UnmetAction", "")
            if (ua = "stop" || ua = "continue")
                s.unmetAction := ua
            else
                s.unmetAction := (oldFail = "skip") ? "continue" : "stop"
            s.fail := (s.unmetAction = "continue") ? "skip" : "stop"

            ma := IniRead(file, sec, "MouseAction", "None")
            s.mouseAction := (ma = "Left" || ma = "Right" || ma = "Move") ? ma : "None"
            s.mouseX := ReadIniInt(file, sec, "MouseX", s.x + s.w // 2)
            s.mouseY := ReadIniInt(file, sec, "MouseY", s.y + s.h // 2)
            s.mouseClicks := ReadIniInt(file, sec, "MouseClicks", 1)
            s.mouseClickInterval := ReadIniInt(file, sec, "MouseClickInterval", 80)
            s.mouseMoveSpeed := ReadIniInt(file, sec, "MouseMoveSpeed", 0)

            b := IniRead(file, sec, "Button", "Left")
            s.button := (b = "Right") ? "Right" : (b = "Move") ? "Move" : "Left"
            s.clicks := ReadIniInt(file, sec, "Clicks", 1)
            s.clickInterval := ReadIniInt(file, sec, "ClickInterval", 80)
            s.moveSpeed := ReadIniInt(file, sec, "MoveSpeed", 0)
            s.keys := IniRead(file, sec, "Keys", "")
            s.keyMode := (IniRead(file, sec, "KeyMode", "send") = "text") ? "text" : "send"
            s.keyRepeats := ReadIniInt(file, sec, "KeyRepeats", 1)
            s.keyInterval := ReadIniInt(file, sec, "KeyInterval", 100)
            s.delay := ReadIniInt(file, sec, "Delay", 1000)
            s.after := ReadIniInt(file, sec, "After", 300)
            newSteps.Push(s)
        }

        steps := newSteps
        selectedIndex := 0
        CONFIG_FILE := file
        return true
    } catch as e {
        Log("载入配置失败 · " e.Message, "error")
        return false
    }
}

ReadIniInt(file, sec, key, def) {
    v := IniRead(file, sec, key, "")
    if IsIntegerText(v)
        return Integer(v)
    return def
}

Main_Close(*) {
    global running
    if (running) {
        if (MsgBox("队列正在运行，确定退出？", "退出", "YesNo Icon?") != "Yes")
            return
    }
    SaveConfig()
    ExitApp()
}

CleanUp(*) {
    SetTimer(CheckOcrServer, 0)
    try SaveConfig()
    StopOcrServer()
}

; ============================================================
;  Small helpers
; ============================================================

TypeIndex(t) {
    return (t = "OCR") ? 1 : (t = "Click") ? 2 : 3
}

TypeFromIndex(i) {
    return (i = 1) ? "OCR" : (i = 2) ? "Click" : "Delay"
}

TypeLabel(t) {
    return (t = "OCR") ? "OCR" : (t = "Click") ? "鼠标" : (t = "Keyboard") ? "键盘" : "延时"
}

StepTypeLabel(s) {
    if (s.type = "Click")
        return (s.button = "Move") ? "移动" : "点击"
    return TypeLabel(s.type)
}

ButtonLabel(b) {
    return (b = "Right") ? "右键" : (b = "Move") ? "移动" : "左键"
}

RequireInt(value, label, minVal, maxVal) {
    txt := Trim(value)
    if !IsIntegerText(txt)
        throw ValueError(label " 必须是整数。")
    n := Integer(txt)
    if (n < minVal || n > maxVal)
        throw ValueError(label " 必须在 " minVal " 到 " maxVal " 之间。")
    return n
}

IsIntegerText(s) {
    return RegExMatch(Trim(s), "^-?\d+$") ? true : false
}

VirtualScreen() {
    x := DllCall("GetSystemMetrics", "Int", 76, "Int")
    y := DllCall("GetSystemMetrics", "Int", 77, "Int")
    w := DllCall("GetSystemMetrics", "Int", 78, "Int")
    h := DllCall("GetSystemMetrics", "Int", 79, "Int")
    return {x: x, y: y, w: w, h: h}
}

ValidatePoint(x, y) {
    vs := VirtualScreen()
    if (x < vs.x || y < vs.y || x >= vs.x + vs.w || y >= vs.y + vs.h)
        throw ValueError("坐标 (" x "," y ") 不在屏幕范围内。")
}

ValidateRegion(x, y, w, h) {
    if (w < 2 || h < 2)
        throw ValueError("OCR 区域至少需要 2 × 2 像素。")
    vs := VirtualScreen()
    if (x < vs.x || y < vs.y || x + w > vs.x + vs.w || y + h > vs.y + vs.h)
        throw ValueError("OCR 区域超出屏幕范围。请重新框选。")
}

JoinArray(arr, sep) {
    out := ""
    for v in arr
        out .= (out = "" ? "" : sep) v
    return out
}
