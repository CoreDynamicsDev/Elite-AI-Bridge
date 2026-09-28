import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs
import "components"

Window {
    id: root
    visible: false
    width: 2560
    height: 1440
    minimumWidth: 1280
    minimumHeight: 720
    color: "#070706"
    title: "Elite AI Bridge 1.0"
    property bool closeAuthorized: false
    // Universal launch cinematic. It runs before wizard, startup health, or cockpit.
    property bool startupMovieVisible: false // v0.30.35: startup movie disabled during development
    property bool startupMovieEnding: false
    // v0.30.40: overlay remains lazy-created after Bridge startup.
    // It is instantiated only after the pilot explicitly enables it this session.
    property bool overlayRuntimeRequested: false

    // Treat the Windows title-bar X / Alt+F4 exactly like the cockpit EXIT control.
    // The first native close is intercepted, Bridge flushes pending settings and
    // shuts the backend down, then the authorized close is allowed through.
    onClosing: function(close) {
        if (!root.closeAuthorized) {
            close.accepted = false
            root.closeAuthorized = true
            bridge.exitBridge()
        }
    }

    readonly property real designWidth: 2560.0
    readonly property real designHeight: 1440.0
    // Qt 6 exposes the window in device-independent pixels. Scaling from the
    // logical window size, then letting Qt apply the monitor DPR, keeps the same
    // cockpit proportions on 2K, 4K and 5K panels at any normal Windows DPI.
    readonly property real scaleUnit: Math.max(0.50, Math.min(width/designWidth, height/designHeight))
    readonly property int layoutScalePercent: Math.round(scaleUnit*100)
    readonly property real m: Math.max(10, 20*scaleUnit)
    readonly property real gap: Math.max(8, 14*scaleUnit)
    readonly property real navW: Math.max(250, 338*scaleUnit)
    readonly property real topH: Math.max(110, 145*scaleUnit)
    readonly property real infoH: Math.max(100, 122*scaleUnit)

    property color green: "#2aff80"
    property color green2: "#00ff66"
    property color dimGreen: "#125e36"
    property color amber: "#d6a540"
    property color red: "#ff493e"
    property color whiteText: "#d9d4c2"
    property color muted: "#859086"
    property color screen: "#070907"
    property int currentPage: 0 // LIVE is always the startup/default page
    property int previousPage: 0
    property bool introManualOpen: false
    property bool introSessionDismissed: false
    property int introStep: 0
    property bool introDontShowAgain: false
    property string introApiKeyDraft: ""
    property string introCommanderDraft: ""
    property real introVoiceVolumeDraft: 50
    property real introVoiceSpeedDraft: 1.10
    property bool wizardBackendSynced: false
    property bool wizardLastConnected: false
    property int wizardBackendStep: -1
    readonly property bool introVisible: !root.startupMovieVisible && !introSessionDismissed && (introManualOpen || bridge.firstRunSetupEnabled)
    property int lastUiPageHintSerial: 0
    property int lastPageHelpCompletedSerial: 0
    property bool uiContextBackendSeen: false
    property bool pendingLiveOrientation: false
    property bool firstOrientationActive: false
    property bool firstOrientationPaused: false
    property int firstOrientationIndex: 0
    property int firstOrientationResumeStep: 0
    property int firstOrientationPhase: 0 // 0 module-bank intro, 1 module button, 2 page walkthrough
    property bool orientationLockNoticeVisible: false
    property bool tutorialIntroArrowVisible: false
    property bool wizardCallNameTouched: false
    property bool wizardPttTrainingDone: false
    property bool wizardPttMapStarted: false
    property bool wizardTalkLevelTouched: false
    property bool wizardAudioTested: false
    property bool wizardUpgradeOnly: false
    property string wizardPath: "" // CORE or COPILOT; chosen explicitly on first-run
    readonly property var wizardSteps: wizardUpgradeOnly ? [
        {"label":"AI CO-PILOT","step":2}, {"label":"BRIDGE VOICE","step":3}, {"label":"PUSH-TO-TALK","step":4}, {"label":"SYSTEM HEALTH","step":6}
    ] : (wizardPath === "CORE" ? [
        {"label":"CHOOSE MODE","step":0}, {"label":"AUDIO","step":1}, {"label":"BRIDGE VOICE","step":3}, {"label":"SYSTEM HEALTH","step":6}
    ] : (wizardPath === "COPILOT" ? [
        {"label":"CHOOSE MODE","step":0}, {"label":"AUDIO","step":1}, {"label":"AI CO-PILOT","step":2}, {"label":"BRIDGE VOICE","step":3}, {"label":"PUSH-TO-TALK","step":4}, {"label":"SYSTEM HEALTH","step":6}
    ] : [{"label":"CHOOSE MODE","step":0}]))
    property bool wizardIntroLocked: true
    property bool wizardIntroNarrationSeen: false
    property bool wizardReadinessScanActive: false
    property int wizardReadinessScanIndex: -1
    property bool startupPreflightSessionDismissed: false
    property bool startupPreflightLatched: false
    property bool startupPreflightDecisionMade: false
    property bool startupPreflightRequested: false
    property bool startupPreflightScanActive: false
    property int startupPreflightScanIndex: -1
    property bool startupPreflightDetails: false
    readonly property bool startupPreflightVisible: !root.introVisible && root.startupPreflightLatched && !root.startupPreflightSessionDismissed // v0.30.25: optional user-selected startup systems check
    readonly property var firstOrientationPages: [0, 2, 3, 1, 4, 8]

    function startupPreflightRows() {
        var rows = []
        var base = bridge.setupPreflightRows || []
        for (var i = 0; i < base.length; i++) rows.push(base[i])
        rows.push({
            "label": "Display",
            "status": "READY",
            "detail": bridge.activeMonitorName + " // " + bridge.activeMonitorResolution + " // Windows " + bridge.activeMonitorDpiScale
        })
        rows.push({
            "label": "Market data",
            "status": bridge.tradeMarketRows > 0 ? "READY" : "WAITING",
            "detail": bridge.tradeMarketRows > 0 ? (bridge.tradeMarketRows + " market entries available") : "Loads automatically when Elite market data becomes available."
        })
        return rows
    }

    function runStartupPreflight(forceRun) {
        if (!root.startupPreflightVisible || !bridge.connected) return
        if (root.startupPreflightRequested && !forceRun) return
        root.startupPreflightRequested = true
        root.startupPreflightScanIndex = 0
        root.startupPreflightScanActive = true
        bridge.requestCommand("setup_preflight")
        startupPreflightScanTimer.restart()
    }

    function applyUiDirectorHint() {
        var serial = Number(bridge.uiPageHintSerial || 0)
        if (serial <= lastUiPageHintSerial) return
        lastUiPageHintSerial = serial
        if (introVisible) return
        var page = Number(bridge.uiPageHint)
        if (page < 0 || page > 10) return
        currentPage = page
        var workspace = String(bridge.uiWorkspaceHint || "").toLowerCase()
        if (page === 2) {
            if (workspace === "res_finder") combatPage.utilityMode = 1
            else if (workspace === "tactical") combatPage.utilityMode = 0
        } else if (page === 3) {
            if (workspace === "route_finder") tradePage.tradeView = 1
            else if (workspace === "loop_setup" || workspace === "trade_loop") tradePage.tradeView = 0
            else if (workspace === "best_trade") tradePage.tradeView = 2
        }
    }

    function uiPageName(page) {
        if (page === 5) return "OVERVIEW > COMMANDER RECORDS"
        if (page === 6) return "SETUP > AI & VOICE"
        if (page === 7) return "SETUP > AUDIO"
        if (page === 9) return "SETUP > DISPLAY"
        if (page === 10) return "SETUP > CONTROLS"
        var names = ["OVERVIEW","NAVIGATION","COMBAT","TRADE","COLONIZATION","OVERVIEW","SETUP","SETUP","SETUP","SETUP","SETUP"]
        return (page >= 0 && page < names.length) ? names[page] : "OVERVIEW"
    }

    function currentWorkspaceKey() {
        if (currentPage === 2) return combatPage.utilityMode === 1 ? "res_finder" : "tactical"
        if (currentPage === 3) return tradePage.tradeView === 2 ? "best_trade" : (tradePage.tradeView === 1 ? "route_finder" : "loop_setup")
        return "main"
    }

    function currentUiContextLabel() {
        var base = uiPageName(currentPage)
        var ws = currentWorkspaceKey()
        if (ws === "res_finder") return base + " > RES FINDER"
        if (ws === "tactical") return base + " > TACTICAL"
        if (ws === "best_trade") return base + " > BEST TRADE"
        if (ws === "route_finder") return base + " > ROUTE FINDER"
        if (ws === "loop_setup" || ws === "trade_loop") return base + " > TRADE LOOP"
        return base
    }

    function publishUiContext() {
        if (bridge && bridge.connected) bridge.setUiContext(currentPage, currentWorkspaceKey())
    }

    function launchLiveOrientation(forceRun) {
        // After the first completed tour, the Page 7 / Setup toggle becomes an
        // opt-in replay switch. Completion must not suppress that replay.
        if (!forceRun && !bridge.liveOrientationEnabled) return
        pendingLiveOrientation = true
        currentPage = 0
        liveOrientationLaunchTimer.restart()
    }

    function startFirstOrientation() {
        firstOrientationActive = true
        firstOrientationPaused = false
        firstOrientationIndex = 0
        firstOrientationResumeStep = 0
        firstOrientationPhase = 0
        currentPage = 0
        bridge.setWizardRuntimePaused(true)
        root.orientationLockNoticeVisible = true
        orientationLockNoticeTimer.restart()
        root.tutorialIntroArrowVisible = true
        bridge.announceOrientationStart()
        firstOrientationPageTimer.restart()
    }

    function pauseFirstOrientation() {
        if (!firstOrientationActive || firstOrientationPaused) return
        firstOrientationResumeStep = Math.max(0, Number(bridge.pageHelpStep || 0))
        firstOrientationPaused = true
        bridge.stopPageHelp()
        bridge.playUiCue("nav")
    }

    function resumeFirstOrientation() {
        if (!firstOrientationActive || !firstOrientationPaused) return
        firstOrientationPaused = false
        firstOrientationPageTimer.restart()
        bridge.playUiCue("confirm")
    }

    function stopFirstOrientation() {
        if (!firstOrientationActive) return
        bridge.stopPageHelp()
        firstOrientationActive = false
        firstOrientationPaused = false
        firstOrientationPhase = 0
        root.orientationLockNoticeVisible = false
        root.tutorialIntroArrowVisible = false
        pendingLiveOrientation = false
        currentPage = 0
        bridge.setWizardRuntimePaused(false)
        bridge.announceOrientationStopped()
    }

    function finishFirstOrientation() {
        firstOrientationActive = false
        firstOrientationPaused = false
        firstOrientationPhase = 0
        root.orientationLockNoticeVisible = false
        root.tutorialIntroArrowVisible = false
        currentPage = 0
        bridge.markLiveOrientationComplete()
        bridge.setWizardRuntimePaused(false)
        bridge.announceOrientationComplete()
    }

    // First orientation is intentionally brief: introduce the module bank, then
    // visit each main module once while its left-rail button is highlighted. The
    // detailed per-page walkthrough now lives behind the ? button so first launch
    // gets the pilot into the cockpit quickly.
    function advanceFirstOrientation(completedPage) {
        if (!firstOrientationActive || firstOrientationPaused) return

        if (firstOrientationPhase === 0) {
            // The whole BRIDGE MODULES bank was just introduced.
            if (Number(completedPage) !== 0) return
            firstOrientationPhase = 1
            root.tutorialIntroArrowVisible = false
            firstOrientationPageTimer.restart()
            return
        }

        if (firstOrientationPhase === 1) {
            // One concise module description is enough for first launch. Detailed
            // controls remain available from the ? button on that page at any time.
            if (Number(completedPage) !== 0) return
            firstOrientationIndex += 1
            firstOrientationResumeStep = 0
            if (firstOrientationIndex >= firstOrientationPages.length) {
                finishFirstOrientation()
                return
            }
            firstOrientationPageTimer.restart()
            return
        }
    }

    Timer {
        id: liveOrientationLaunchTimer
        interval: 900
        repeat: false
        onTriggered: {
            if (!root.pendingLiveOrientation) return
            if (root.introVisible || !bridge.connected) { restart(); return }
            root.pendingLiveOrientation = false
            root.currentPage = 0
            // A requested replay runs the same guided cockpit tour, even if the
            // one-time completion flag is already set. The flag only controls
            // whether the first run is mandatory.
            root.startFirstOrientation()
        }
    }

    Timer {
        id: startupPreflightScanTimer
        interval: 125
        repeat: true
        onTriggered: {
            if (!root.startupPreflightScanActive) { stop(); return }
            root.startupPreflightScanIndex += 1
            var total = root.startupPreflightRows().length
            if (root.startupPreflightScanIndex >= total) {
                root.startupPreflightScanActive = false
                root.startupPreflightScanIndex = -1
                stop()
                bridge.playUiCue(bridge.setupReady ? "confirm" : "warn")
            }
        }
    }

    Timer {
        id: wizardReadinessScanTimer
        interval: 135
        repeat: true
        onTriggered: {
            if (!root.wizardReadinessScanActive) { stop(); return }
            root.wizardReadinessScanIndex += 1
            var total = bridge.setupPreflightRows ? bridge.setupPreflightRows.length : 0
            if (root.wizardReadinessScanIndex >= total) {
                root.wizardReadinessScanActive = false
                root.wizardReadinessScanIndex = -1
                stop()
                bridge.playUiCue(bridge.setupReady ? "confirm" : "warn")
            }
        }
    }

    Timer {
        id: wizardIntroSafetyTimer
        interval: 45000
        repeat: false
        onTriggered: {
            if (root.introVisible && root.introStep === 0) root.wizardIntroLocked = false
        }
    }

    Timer {
        id: firstOrientationPageTimer
        interval: 620
        repeat: false
        onTriggered: {
            if (!root.firstOrientationActive || root.firstOrientationPaused || root.introVisible || !bridge.connected) return
            if (root.firstOrientationPhase === 0) {
                root.currentPage = 0
                bridge.startPageHelpSegment(0, 0, 0)
            } else if (root.firstOrientationPhase === 1) {
                var navStep = root.firstOrientationIndex + 1
                var destinationPage = Number(root.firstOrientationPages[root.firstOrientationIndex])
                root.currentPage = destinationPage
                bridge.playUiCue("nav")
                // Highlight the module button only after its destination is on screen.
                bridge.startPageHelpSegment(0, navStep, navStep)
            }
        }
    }

    function wizardStepPosition(step) {
        for (var i=0; i<root.wizardSteps.length; i++) if (Number(root.wizardSteps[i].step) === Number(step)) return i
        return 0
    }

    function wizardNextPhysicalStep(step) {
        var pos = root.wizardStepPosition(step)
        if (pos >= root.wizardSteps.length-1) return step
        return Number(root.wizardSteps[pos+1].step)
    }

    function wizardPreviousPhysicalStep(step) {
        var pos = root.wizardStepPosition(step)
        if (pos <= 0) return step
        return Number(root.wizardSteps[pos-1].step)
    }

    function selectWizardPath(path) {
        // Selection is intentionally local. Choosing a card must not interrupt the
        // opening voice briefing or change the active Bridge mode. NEXT commits it.
        root.wizardPath = path
    }

    function requestBridgeExit() {
        root.closeAuthorized = true
        bridge.exitBridge()
    }

    function openFullSetupWizard() {
        root.wizardUpgradeOnly = false
        root.wizardPath = ""
        root.introStep = 0
        root.wizardBackendStep = 0
        root.introManualOpen = true
        root.introSessionDismissed = false
        root.introDontShowAgain = !bridge.firstRunSetupEnabled
        bridge.playUiCue("confirm")
    }

    function openCopilotUpgradeWizard() {
        root.wizardUpgradeOnly = true
        root.wizardPath = "COPILOT"
        root.introStep = 2
        root.wizardBackendStep = 2
        root.introManualOpen = true
        root.introSessionDismissed = false
        root.introDontShowAgain = !bridge.firstRunSetupEnabled
        bridge.playUiCue("confirm")
    }

    function switchWizardToCore() {
        root.wizardUpgradeOnly = false
        root.wizardPath = "CORE"
        bridge.setSetupValue("bridge_mode", "CORE")
        root.introApiKeyDraft = ""
        root.introStep = 0
        root.wizardBackendStep = 0
        root.narrateWizardPage(0)
    }

    function pageHelpTarget(page, step) {
        if (page === 0) {
            if (step === 0) return bridgeModulesGuideTarget
            var moduleIndex = step - 1
            return (moduleIndex >= 0 && moduleIndex < navModuleRepeater.count) ? navModuleRepeater.itemAt(moduleIndex) : bridgeModulesGuideTarget
        }
        if (page === 1) return step === 0 ? navTop : (step === 1 ? routeDisplay : navBottom)
        if (page === 2) return step === 0 ? combatCommandRack : (step === 1 ? combatModeBank : combatRight)
        if (page === 3) {
            if (step === 0) return tradeTabs
            if (tradePage.tradeView === 2) return step === 1 ? bestTradeSearchButton : bestTradeList
            if (tradePage.tradeView === 1) return step === 1 ? tradeFinderControls : tradeFinderBottomActions
            return step === 1 ? tradeSetupTop : tradePage
        }
        if (page === 4) return step === 0 ? projectOverview : (step === 1 ? supplyPanel : nextDeliveryPanel)
        if (page === 5) return step === 0 ? commanderTop : (step === 1 ? commanderBottom : commanderPage)
        if (page === 6) return step === 0 ? aiTop : (step === 1 ? aiBottom : aiVoicePage)
        if (page === 7) return step === 0 ? audioTop : audioPage
        if (page === 8) return setupScroll
        if (page === 9) return displayMainPanel
        if (page === 10) return step === 0 ? controlsPttPanel : (step === 1 ? controlsCommandMapPanel : controlsEliteBindsPanel)
        return null
    }

    // First-run audio/runtime state is synchronized only after the backend is
    // actually online. This avoids losing the opening music/narration commands
    // during backend startup.
    function narrateWizardPage(step) {
        // Use seven explicit no-argument bridge slots. Page identity never crosses
        // the frontend/backend boundary as a QVariant integer.
        if (step === 0) bridge.narrateWizardPage1()
        else if (step === 1) bridge.narrateWizardPage2()
        else if (step === 2) bridge.narrateWizardPage3()
        else if (step === 3) bridge.narrateWizardPage4()
        else if (step === 4) bridge.narrateWizardPage5()
        else if (step === 5) bridge.narrateWizardPage6()
        else bridge.narrateWizardPage7()
    }

    function syncWizardWithBackend() {
        if (!bridge.connected) {
            wizardLastConnected = false
            return
        }
        if (!wizardLastConnected) {
            wizardLastConnected = true
            wizardBackendSynced = false
            wizardBackendStep = -1
        }
        if (introVisible) {
            if (!wizardBackendSynced) {
                wizardBackendSynced = true
                wizardBackendStep = introStep
                bridge.startWizard(introStep)
            }
            // Backend state refreshes are synchronization only. They must never
            // create narration. Back/Next are the single authoritative page-voice path.
        } else {
            if (!wizardBackendSynced || wizardBackendStep !== -99) {
                wizardBackendSynced = true
                wizardBackendStep = -99
                bridge.stopWizard()
            }
        }
    }
    onStartupPreflightVisibleChanged: {
        if (startupPreflightVisible) {
            startupPreflightDetails = false
            startupPreflightRequested = false
            if (bridge.connected) Qt.callLater(root.runStartupPreflight)
        } else {
            startupPreflightScanActive = false
            startupPreflightScanIndex = -1
            startupPreflightScanTimer.stop()
        }
    }

    onIntroVisibleChanged: {
        if(introVisible) {
            introCommanderDraft=bridge.setupCommanderAddress
            introVoiceVolumeDraft=bridge.voiceVolume
            introVoiceSpeedDraft=bridge.voiceSpeed
            wizardPttTrainingDone=false
            wizardPttMapStarted=false
            wizardTalkLevelTouched=false
            wizardAudioTested=false
            if (introStep === 0) {
                wizardIntroLocked=true
                wizardIntroNarrationSeen=false
                wizardIntroSafetyTimer.restart()
            }
        }
        wizardBackendSynced=false
        wizardBackendStep=-1
        syncWizardWithBackend()
    }
    onIntroStepChanged: {
        // Do not narrate from property/state changes. A single click on Back/Next
        // owns exactly one destination-page narration request.
        wizardBackendStep = introStep
        if (introStep === 0 && introVisible) {
            wizardIntroLocked=true
            wizardIntroNarrationSeen=false
            wizardIntroSafetyTimer.restart()
        } else if (introStep !== 0) {
            wizardIntroLocked=false
        }
        if (introStep === 1 && introVisible && bridge.connected) {
            bridge.requestCommand("audio_rescan")
        }
        if (introStep === 3) {
            introVoiceVolumeDraft = bridge.voiceVolume
            introVoiceSpeedDraft = bridge.voiceSpeed
        }
        if (introStep === 6 && introVisible && bridge.connected) {
            bridge.requestCommand("setup_preflight")
            wizardReadinessScanIndex = 0
            wizardReadinessScanActive = true
            wizardReadinessScanTimer.restart()
        }
        if (introVisible && !bridge.connected) syncWizardWithBackend()
    }
    Component.onCompleted: { startupPreflightLatched=bridge.startupPreflightEnabled; overlayRuntimeRequested=bridge.gameOverlayEnabled; syncWizardWithBackend(); publishUiContext() }
    Connections {
        target: bridge
        function onStateChanged() {
            root.syncWizardWithBackend()
            root.applyUiDirectorHint()
            if (bridge.connected && !root.startupPreflightDecisionMade && !root.introVisible) {
                // v0.30.24: startup health is explicitly opt-in. Missing optional
                // dependencies never force this screen when the pilot disabled it.
                root.startupPreflightDecisionMade = true
            }
            if (root.startupPreflightVisible && bridge.connected && !root.startupPreflightRequested) root.runStartupPreflight()
            if (!bridge.connected) root.startupPreflightRequested = false
            if (root.introVisible && root.introStep === 0 && root.wizardIntroLocked) {
                if (bridge.wizardNarrationActive) root.wizardIntroNarrationSeen = true
                else if (root.wizardIntroNarrationSeen) {
                    root.wizardIntroLocked = false
                    wizardIntroSafetyTimer.stop()
                }
            }
            if (root.wizardPttMapStarted && bridge.pttStatus === "READY") {
                root.wizardPttTrainingDone = true
                root.wizardPttMapStarted = false
            }
            var completedSerial = Number(bridge.pageHelpCompletedSerial || 0)
            if (completedSerial > root.lastPageHelpCompletedSerial) {
                root.lastPageHelpCompletedSerial = completedSerial
                if (root.firstOrientationActive) root.advanceFirstOrientation(Number(bridge.pageHelpCompletedPage))
            }
            if (bridge.connected && !root.uiContextBackendSeen) {
                root.uiContextBackendSeen = true
                root.publishUiContext()
            } else if (!bridge.connected) {
                root.uiContextBackendSeen = false
            }
        }
    }
    onCurrentPageChanged: {
        if (!root.firstOrientationActive && bridge.pageHelpActive && bridge.pageHelpPage !== currentPage) bridge.stopPageHelp()
        if (currentPage === 2 && previousPage !== 2) bridge.requestCommand("combat_enter")
        else if (previousPage === 2 && currentPage !== 2) bridge.requestCommand("combat_leave")
        previousPage = currentPage
        publishUiContext()
    }

    // Canonical portrait art pack is integrated for milestone builds.
    function normalizeShipArtKey(shipModelText) {
        var raw = String(shipModelText || "").toLowerCase().trim()
        if (!raw || raw === "-") return "unknown_target"
        var key = raw.replace(/\(.*?\)/g, "")
                     .replace(/^ship[\/: _-]*/, "")
                     .replace(/[^a-z0-9]+/g, "_")
                     .replace(/^_+|_+$/g, "")

        var aliases = {
            "sidewinder_mk_i": "sidewinder",
            "federation_corvette": "federal_corvette",
            "federation_dropship": "federal_dropship",
            "federation_gunship": "federal_gunship",
            "federation_assault_ship": "federal_assault_ship",
            "federation_dropship_mkii": "federal_assault_ship",
            "federation_dropship_mk_ii": "federal_assault_ship",
            "empire_courier": "imperial_courier",
            "empire_eagle": "imperial_eagle",
            "empire_trader": "imperial_clipper",
            "cutter": "imperial_cutter",
            "type6": "type_6_transporter",
            "type_6": "type_6_transporter",
            "type7": "type_7_transporter",
            "type_7": "type_7_transporter",
            "type8": "type_8_transporter",
            "type_8": "type_8_transporter",
            "type9": "type_9_heavy",
            "type_9": "type_9_heavy",
            "type10": "type_10_defender",
            "type_10": "type_10_defender",
            "type11": "type_11_prospector",
            "type_11": "type_11_prospector",
            "cobramkiii": "cobra_mk_iii",
            "cobra_mk_3": "cobra_mk_iii",
            "cobramkiv": "cobra_mk_iv",
            "cobra_mk_4": "cobra_mk_iv",
            "cobramkv": "cobra_mk_v",
            "cobra_mk_5": "cobra_mk_v",
            "vipermkiii": "viper_mk_iii",
            "viper_mk_3": "viper_mk_iii",
            "vipermkiv": "viper_mk_iv",
            "viper_mk_4": "viper_mk_iv",
            "krait_mkii": "krait_mk_ii",
            "kraitmk2": "krait_mk_ii",
            "krait_mk2": "krait_mk_ii",
            "pythonmkii": "python_mk_ii",
            "python_mk2": "python_mk_ii",
            "eagle": "eagle_mk_ii",
            "eaglemkii": "eagle_mk_ii",
            "condor": "f63_condor_federal_fighter",
            "f63_condor": "f63_condor_federal_fighter",
            "imperial_fighter": "gu_97_imperial_fighter",
            "gu97": "gu_97_imperial_fighter",
            "gu_97": "gu_97_imperial_fighter",
            "fdl": "fer_de_lance",
            "asp": "asp_explorer",
            "dbx": "diamondback_explorer",
            "dbs": "diamondback_scout",
            "fleetcarrier": "fleet_carrier",
            "carrier": "fleet_carrier",
            "orbis": "orbis_station",
            "ocellus": "ocellus_station",
            "outpost": "outpost_station",
            "station": "orbis_station",
            "coriolis_station": "coriolis",
            "srv_scarab": "scarab",
            "scorpion": "scorpion_srv",
            "rhino": "rhino_srv",
            "blackbox": "black_box",
            "escapepod": "escape_pod",
            "unknown": "unknown_target",
            "unknown_ship": "unknown_target",
            "thargoidscout": "marauder_thargoid_scout",
            "scout": "marauder_thargoid_scout",
            "cyclops": "cyclop"
        }

        if (aliases[key]) return aliases[key]
        if (key.indexOf("fleet") !== -1 && key.indexOf("carrier") !== -1) return "fleet_carrier"
        if (key.indexOf("mega") !== -1) return "megaship"
        if (key.indexOf("limpet") !== -1) return "limpet"
        if (key.indexOf("escape") !== -1 && key.indexOf("pod") !== -1) return "escape_pod"
        if (key.indexOf("black") !== -1 && key.indexOf("box") !== -1) return "black_box"
        if (key.indexOf("thargoid") !== -1 && key.indexOf("basilisk") !== -1) return "thargoid_basilisk"
        if (key.indexOf("thargoid") !== -1 && key.indexOf("medusa") !== -1) return "thargoid_medusa"
        if (key.indexOf("thargoid") !== -1 && key.indexOf("hydra") !== -1) return "thargoid_hydra"
        if (key.indexOf("thargoid") !== -1 && key.indexOf("orthrus") !== -1) return "thargoid_orthrus"
        if (key.indexOf("thargoid") !== -1 && key.indexOf("glaive") !== -1) return "thargoid_glaive"
        if (key.indexOf("thargoid") !== -1 && key.indexOf("scythe") !== -1) return "thargoid_scythe"
        if (key.indexOf("thargoid") !== -1 && key.indexOf("titan") !== -1) return "thargoid_titan"
        return key
    }

    function shipArtSource(shipModelText) {
        // Release art pack: only portraits physically packaged with Bridge.
        var fileMap = {
            "adder": "ship_adder.png",
            "alliance_challenger": "ship_alliance_challenger.png",
            "alliance_chieftain": "ship_alliance_chieftain.png",
            "alliance_crusader": "ship_alliance_crusader.png",
            "anaconda": "ship_anaconda.png",
            "asp_explorer": "ship_asp_explorer.png",
            "asp_scout": "ship_asp_scout.png",
            "beluga_liner": "ship_beluga_liner.png",
            "caspian_explorer": "ship_caspian_explorer.png",
            "cobra_mk_iii": "ship_cobra_mk_iii.png",
            "cobra_mk_iv": "ship_cobra_mk_iv.png",
            "cobra_mk_v": "ship_cobra_mk_v.png",
            "corsair": "ship_corsair.png",
            "diamondback_explorer": "ship_diamondback_explorer.png",
            "diamondback_scout": "ship_diamondback_scout.png",
            "dolphin": "ship_dolphin.png",
            "eagle_mk_ii": "ship_eagle_mk_ii.png",
            "federal_assault_ship": "ship_federal_assault_ship.png",
            "federal_corvette": "ship_federal_corvette.png",
            "federal_dropship": "ship_federal_dropship.png",
            "federal_gunship": "ship_federal_gunship.png",
            "fer_de_lance": "ship_fer_de_lance.png",
            "hauler": "ship_hauler.png",
            "imperial_clipper": "ship_imperial_clipper.png",
            "imperial_courier": "ship_imperial_courier.png",
            "imperial_cutter": "ship_imperial_cutter.png",
            "imperial_eagle": "ship_imperial_eagle.png",
            "keelback": "ship_keelback.png",
            "kestrel_mk_ii": "ship_kestrel_mk_ii.png",
            "krait_mk_ii": "ship_krait_mk_ii.png",
            "krait_phantom": "ship_krait_phantom.png",
            "lynx_highliner": "ship_lynx_highliner.png",
            "mamba": "ship_mamba.png",
            "mandalay": "ship_mandalay.png",
            "orca": "ship_orca.png",
            "panther_clipper_mk_ii": "ship_panther_clipper_mk_ii.png",
            "python": "ship_python.png",
            "python_mk_ii": "ship_python_mk_ii.png",
            "sidewinder_mk_i": "ship_sidewinder_mk_i.png",
            "type_10_defender": "ship_type_10_defender.png",
            "type_11_prospector": "ship_type_11_prospector.png",
            "type_6_transporter": "ship_type_6_transporter.png",
            "type_7_transporter": "ship_type_7_transporter.png",
            "type_8_transporter": "ship_type_8_transporter.png",
            "type_9_heavy": "ship_type_9_heavy.png",
            "viper_mk_iii": "ship_viper_mk_iii.png",
            "viper_mk_iv": "ship_viper_mk_iv.png",
            "vulture": "ship_vulture.png"
        }
        var key = normalizeShipArtKey(shipModelText)
        if (fileMap[key]) return "assets/ship_art/" + fileMap[key]
        return "assets/ship_unknown.png"
    }

    function fmtNumber(value) {
        var n = Number(value || 0)
        return n.toLocaleString(Qt.locale("en_US"), 'f', 0)
    }

    function listIndexOf(list, value) {
        if (!list) return 0
        for (var i = 0; i < list.length; i++) {
            if (String(list[i]) === String(value)) return i
        }
        return 0
    }

    // Deep chassis.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#22201c" }
            GradientStop { position: .10; color: "#12110f" }
            GradientStop { position: .88; color: "#0b0a09" }
            GradientStop { position: 1.0; color: "#1a1815" }
        }
        border.color: "#050504"
        border.width: Math.max(3,5*root.scaleUnit)
    }
    Rectangle {
        anchors.fill: parent; anchors.margins: Math.max(5,8*root.scaleUnit)
        color: "transparent"; border.color: "#786c53"; border.width: 1; opacity: .72
    }
    // Side rails make the shell read as a physical object.
    Rectangle { x: 0; y: 0; width: Math.max(10,17*root.scaleUnit); height: parent.height; color: "#090807"; border.color: "#3c3830"; border.width: 1 }
    Rectangle { anchors.right: parent.right; y: 0; width: Math.max(10,17*root.scaleUnit); height: parent.height; color: "#090807"; border.color: "#3c3830"; border.width: 1 }

    // Header assembly.
    MetalPanel {
        id: header
        x: root.m; y: root.m
        width: root.width-root.m*2; height: root.topH
        panelColor: "#0a0d0a"; crt: false; heavy: true

        Rectangle {
            id: titleBox
            width: 640*root.scaleUnit; height: 74*root.scaleUnit
            anchors.left: parent.left; anchors.leftMargin: 28*root.scaleUnit
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -10*root.scaleUnit
            color: "#080a08"
            border.color: "#6d644f"
            border.width: 2
            Rectangle { anchors.fill: parent; anchors.margins: 5*root.scaleUnit; color: "transparent"; border.color: "#252820"; border.width: 1 }
            Rectangle { x: 10*root.scaleUnit; y: 10*root.scaleUnit; width: parent.width-20*root.scaleUnit; height: 6*root.scaleUnit; color: "#111410"; opacity: .85 }
            Rectangle { x: 10*root.scaleUnit; y: parent.height-16*root.scaleUnit; width: parent.width-20*root.scaleUnit; height: 6*root.scaleUnit; color: "#111410"; opacity: .85 }
            Text {
                text: "ELITE AI BRIDGE"
                color: root.whiteText
                font.family: "Consolas"; font.bold: true
                font.pixelSize: Math.max(34,54*root.scaleUnit)
                anchors.centerIn: parent
            }
        }
        VentModule {
            id: headerVent
            width: 360*root.scaleUnit; height: 82*root.scaleUnit
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            animated: true
            phase: bridge.pulse
            scaleUnit: root.scaleUnit
            showFan: true
            rows: 4
            columns: 10
        }



        Item {
            id: leftConduit
            width: 182*root.scaleUnit; height: 80*root.scaleUnit
            anchors.right: headerVent.left; anchors.rightMargin: 14*root.scaleUnit
            anchors.verticalCenter: headerVent.verticalCenter
            opacity: 1.0

            Rectangle {
                x: parent.width*0.02; y: parent.height*0.14
                width: parent.width*0.28; height: parent.height*0.72; radius: 4*root.scaleUnit
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#2b2a27" }
                    GradientStop { position: 0.30; color: "#49463f" }
                    GradientStop { position: 1.0; color: "#161613" }
                }
                border.color: "#85775b"; border.width: 2
                Rectangle { anchors.fill: parent; anchors.margins: 6*root.scaleUnit; color: "transparent"; border.color: "#23231f"; border.width: 1 }
            }
            Repeater {
                model: [0.32, 0.42, 0.52]
                Rectangle {
                    x: parent.width*modelData; y: parent.height*0.34
                    width: parent.width*0.26; height: 8*root.scaleUnit; radius: height/2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#555248" }
                        GradientStop { position: 0.50; color: "#86775b" }
                        GradientStop { position: 1.0; color: "#37342e" }
                    }
                    border.color: "#1a1814"; border.width: 1
                }
            }
            Repeater {
                model: [0.36, 0.52, 0.68]
                Rectangle {
                    width: 9*root.scaleUnit; height: parent.height*0.28; radius: 2*root.scaleUnit
                    x: parent.width*modelData; y: parent.height*0.24
                    color: "#141411"; border.color: "#6b5d46"; border.width: 1
                }
            }
            Repeater {
                model: [0.20, 0.76]
                Rectangle {
                    width: 10*root.scaleUnit; height: 10*root.scaleUnit; radius: 5*root.scaleUnit
                    x: parent.width*modelData; y: parent.height*0.52
                    color: "#161511"; border.color: "#8a7751"; border.width: 1; opacity: .88
                }
            }
            Canvas {
                anchors.fill: parent
                opacity: 0.28
                onPaint: {
                    var c = getContext('2d')
                    c.reset(); c.clearRect(0,0,width,height)
                    c.strokeStyle = 'rgba(75,95,88,0.60)'
                    c.lineWidth = 2
                    c.beginPath(); c.moveTo(width*0.16,height*0.70); c.bezierCurveTo(width*0.28,height*0.64,width*0.34,height*0.58,width*0.42,height*0.48); c.stroke()
                    c.beginPath(); c.moveTo(width*0.22,height*0.70); c.bezierCurveTo(width*0.33,height*0.66,width*0.40,height*0.61,width*0.50,height*0.52); c.stroke()
                }
            }
        }

        Item {
            id: rightConduit
            width: 182*root.scaleUnit; height: 80*root.scaleUnit
            anchors.left: headerVent.right; anchors.leftMargin: 14*root.scaleUnit
            anchors.verticalCenter: headerVent.verticalCenter
            opacity: 1.0

            Rectangle {
                x: parent.width*0.70; y: parent.height*0.14
                width: parent.width*0.28; height: parent.height*0.72; radius: 4*root.scaleUnit
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#161613" }
                    GradientStop { position: 0.70; color: "#49463f" }
                    GradientStop { position: 1.0; color: "#2b2a27" }
                }
                border.color: "#85775b"; border.width: 2
                Rectangle { anchors.fill: parent; anchors.margins: 6*root.scaleUnit; color: "transparent"; border.color: "#23231f"; border.width: 1 }
            }
            Repeater {
                model: [0.42, 0.32, 0.22]
                Rectangle {
                    x: parent.width*modelData; y: parent.height*0.34
                    width: parent.width*0.26; height: 8*root.scaleUnit; radius: height/2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#37342e" }
                        GradientStop { position: 0.50; color: "#86775b" }
                        GradientStop { position: 1.0; color: "#555248" }
                    }
                    border.color: "#1a1814"; border.width: 1
                }
            }
            Repeater {
                model: [0.56, 0.40, 0.24]
                Rectangle {
                    width: 9*root.scaleUnit; height: parent.height*0.28; radius: 2*root.scaleUnit
                    x: parent.width*modelData; y: parent.height*0.24
                    color: "#141411"; border.color: "#6b5d46"; border.width: 1
                }
            }
            Repeater {
                model: [0.14, 0.80]
                Rectangle {
                    width: 10*root.scaleUnit; height: 10*root.scaleUnit; radius: 5*root.scaleUnit
                    x: parent.width*modelData; y: parent.height*0.52
                    color: "#161511"; border.color: "#8a7751"; border.width: 1; opacity: .88
                }
            }
            Canvas {
                anchors.fill: parent
                opacity: 0.28
                onPaint: {
                    var c = getContext('2d')
                    c.reset(); c.clearRect(0,0,width,height)
                    c.strokeStyle = 'rgba(75,95,88,0.60)'
                    c.lineWidth = 2
                    c.beginPath(); c.moveTo(width*0.84,height*0.70); c.bezierCurveTo(width*0.72,height*0.64,width*0.66,height*0.58,width*0.58,height*0.48); c.stroke()
                    c.beginPath(); c.moveTo(width*0.78,height*0.70); c.bezierCurveTo(width*0.67,height*0.66,width*0.60,height*0.61,width*0.50,height*0.52); c.stroke()
                }
            }
        }



        Item {
            id: supportBridgeButton
            width: 360*root.scaleUnit; height: 92*root.scaleUnit
            x: titleBox.x + titleBox.width + Math.max(0, (leftConduit.x - (titleBox.x + titleBox.width) - width) / 2)
            anchors.verticalCenter: parent.verticalCenter
            visible:!root.introVisible
            property real runner: 0.0
            property bool hovered: supportMouse.containsMouse
            property bool demoPress: false
            property bool realPress: supportMouse.pressed
            property bool pressedVisual: demoPress || realPress
            property color supportOrange: "#ff8a18"

            Rectangle {
                x:4*root.scaleUnit; y:5*root.scaleUnit; width:parent.width; height:parent.height
                color:"#000000"; opacity:.68; radius:3*root.scaleUnit
            }
            Rectangle {
                id:supportFace
                anchors.fill:parent
                anchors.topMargin:supportBridgeButton.pressedVisual?3*root.scaleUnit:0
                anchors.bottomMargin:supportBridgeButton.pressedVisual?-3*root.scaleUnit:0
                radius:3*root.scaleUnit
                color:supportBridgeButton.hovered?"#261608":"#0d0b07"
                border.color:supportBridgeButton.supportOrange
                border.width:Math.max(2,3*root.scaleUnit)
                Behavior on anchors.topMargin { NumberAnimation { duration:80 } }
            }
            Rectangle {
                anchors.fill:supportFace; anchors.margins:6*root.scaleUnit; radius:2*root.scaleUnit
                color:"transparent"; border.color:supportBridgeButton.hovered?"#d57a2a":"#7a451d"; border.width:1
            }

            Text {
                x:18*root.scaleUnit; y:(supportBridgeButton.pressedVisual?16:13)*root.scaleUnit; width:parent.width-36*root.scaleUnit
                text:"SUPPORT DEVELOPMENT"
                color:supportBridgeButton.supportOrange; font.family:"Consolas"; font.bold:true
                font.pixelSize:Math.max(14,19*root.scaleUnit); horizontalAlignment:Text.AlignHCenter
            }
            Text {
                id:supportClickCue
                x:14*root.scaleUnit; y:(supportBridgeButton.pressedVisual?51:48)*root.scaleUnit; width:parent.width-28*root.scaleUnit
                text:"☝  CLICK TO TIP // KEEP DEVELOPMENT GOING"
                color:supportBridgeButton.hovered?"#fff0d6":"#ffc27a"; font.family:"Consolas"; font.bold:true
                font.pixelSize:Math.max(11,14*root.scaleUnit); horizontalAlignment:Text.AlignHCenter
                fontSizeMode:Text.HorizontalFit; minimumPixelSize:10
            }

            // A short pulse accompanies the occasional demonstration click.
            Rectangle {
                id:supportPulse
                anchors.centerIn:parent; width:parent.width*.90; height:parent.height*.72; radius:5*root.scaleUnit
                color:"transparent"; border.color:supportBridgeButton.supportOrange; border.width:2
                opacity:0; scale:.94
            }
            SequentialAnimation {
                id:supportPulseAnimation
                NumberAnimation { target:supportPulse; property:"opacity"; from:.72; to:0; duration:520 }
                NumberAnimation { target:supportPulse; property:"scale"; from:.94; to:1.05; duration:1 }
            }

            // Clockwise orange tracer around the perimeter.
            Rectangle {
                id:supportRunner
                width:Math.max(10,13*root.scaleUnit); height:width; radius:width/2
                color:supportBridgeButton.supportOrange
                border.color:"#ffd19a"; border.width:1
                property real perimeter:2*(supportBridgeButton.width+supportBridgeButton.height)
                property real d:supportBridgeButton.runner*perimeter
                x:d<supportBridgeButton.width ? d-width/2 :
                  d<supportBridgeButton.width+supportBridgeButton.height ? supportBridgeButton.width-width/2 :
                  d<2*supportBridgeButton.width+supportBridgeButton.height ? (2*supportBridgeButton.width+supportBridgeButton.height-d)-width/2 : -width/2
                y:d<supportBridgeButton.width ? -height/2 :
                  d<supportBridgeButton.width+supportBridgeButton.height ? (d-supportBridgeButton.width)-height/2 :
                  d<2*supportBridgeButton.width+supportBridgeButton.height ? supportBridgeButton.height-height/2 : (perimeter-d)-height/2
                Rectangle { anchors.centerIn:parent; width:parent.width*2.8; height:width; radius:width/2; color:supportBridgeButton.supportOrange; opacity:.18; z:-1 }
            }
            NumberAnimation on runner { from:0; to:1; duration:3600; loops:Animation.Infinite; running:supportBridgeButton.visible }

            // Every few seconds the control demonstrates a tiny physical click.
            Timer {
                interval:4600; repeat:true; running:supportBridgeButton.visible && !supportBridgeButton.hovered
                onTriggered:{
                    supportBridgeButton.demoPress=true
                    supportPulse.scale=.94
                    supportPulseAnimation.restart()
                    supportDemoRelease.restart()
                }
            }
            Timer {
                id:supportDemoRelease; interval:180; repeat:false
                onTriggered:supportBridgeButton.demoPress=false
            }

            MouseArea {
                id:supportMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
                onPressed:{supportBridgeButton.demoPress=false;bridge.playUiCue("nav");supportPulse.scale=.94;supportPulseAnimation.restart()}
                onClicked:{bridge.playUiCue("confirm");bridge.openSupportPage()}
            }
        }

        Rectangle {
            id: connectionStatus
            width: 410*root.scaleUnit; height:72*root.scaleUnit
            anchors.right: pageHelpButton.left; anchors.rightMargin:12*root.scaleUnit
            anchors.verticalCenter: parent.verticalCenter
            property string eliteState: bridge.eliteTelemetryState
            property color eliteColor: eliteState==="CONNECTED" ? root.green : (eliteState==="WAITING" ? root.amber : root.red)
            property bool voiceOnlyActivity: String(bridge.bridgeState || "").toUpperCase() === "AI SPEAKING"
            property string systemState: !bridge.connected ? "STARTING" : (bridge.bridgeLevel === "bad" ? "ALERT" : ((bridge.bridgeLevel === "warn" && !voiceOnlyActivity) ? "DEGRADED" : "ONLINE"))
            property color systemColor: !bridge.connected ? root.amber : (bridge.bridgeLevel === "bad" ? root.red : ((bridge.bridgeLevel === "warn" && !voiceOnlyActivity) ? root.amber : root.green))
            property bool systemHealthy: bridge.connected && bridge.bridgeLevel !== "bad" && (bridge.bridgeLevel !== "warn" || voiceOnlyActivity)
            property int sweepIndex: 0
            color:"#061008"; border.color: systemColor; border.width:2
            Rectangle { anchors.fill:parent; anchors.margins:4*root.scaleUnit; color:"transparent"; border.color:"#1c3021"; border.width:1 }

            // One compact dual-status instrument replaces the two large healthy-state boxes.
            Rectangle { x:146*root.scaleUnit; y:10*root.scaleUnit; width:1; height:parent.height-20*root.scaleUnit; color:"#314033"; opacity:.85 }

            Rectangle { width:10*root.scaleUnit; height:34*root.scaleUnit; x:14*root.scaleUnit; anchors.verticalCenter:parent.verticalCenter; color:connectionStatus.eliteColor; opacity:.90 }
            Text { text:"ELITE"; x:34*root.scaleUnit; y:13*root.scaleUnit; width:102*root.scaleUnit; color:"#87958b"; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,12*root.scaleUnit); elide:Text.ElideRight }
            Text { text:connectionStatus.eliteState; x:34*root.scaleUnit; y:34*root.scaleUnit; width:102*root.scaleUnit; color:connectionStatus.eliteColor; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(12,15*root.scaleUnit); fontSizeMode:Text.HorizontalFit; minimumPixelSize:11; elide:Text.ElideRight }

            Text { text:"SYSTEMS"; x:162*root.scaleUnit; y:13*root.scaleUnit; width:104*root.scaleUnit; color:"#87958b"; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,12*root.scaleUnit); elide:Text.ElideRight }
            Text { text:connectionStatus.systemState; x:162*root.scaleUnit; y:34*root.scaleUnit; width:104*root.scaleUnit; color:connectionStatus.systemColor; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(12,15*root.scaleUnit); fontSizeMode:Text.HorizontalFit; minimumPixelSize:11; elide:Text.ElideRight }

            Timer {
                interval: 420; repeat:true; running:connectionStatus.systemHealthy && !root.introVisible
                onTriggered: connectionStatus.sweepIndex = (connectionStatus.sweepIndex + 1) % 8
            }
            Row {
                id: systemBars
                spacing:5*root.scaleUnit
                anchors.right:parent.right; anchors.rightMargin:14*root.scaleUnit; anchors.verticalCenter:parent.verticalCenter
                Repeater {
                    model:5
                    Rectangle {
                        width:16*root.scaleUnit; height:30*root.scaleUnit
                        property bool sweepHot: connectionStatus.systemHealthy && connectionStatus.sweepIndex === index
                        property bool sweepTail: connectionStatus.systemHealthy && connectionStatus.sweepIndex === index + 1
                        color:connectionStatus.systemColor
                        border.color:Qt.lighter(connectionStatus.systemColor,1.35); border.width:1
                        opacity:connectionStatus.systemHealthy ? (sweepHot?.98:(sweepTail?.70:.43)) : .78
                        Behavior on opacity { NumberAnimation { duration:180 } }
                        Rectangle { anchors.centerIn:parent; width:parent.width*2.5; height:parent.height*1.45; color:connectionStatus.systemColor; opacity:parent.sweepHot?.10:.025 }
                    }
                }
            }
        }

        MechanicalButton {
            id: pageHelpButton
            width: 260*root.scaleUnit; height: 82*root.scaleUnit
            anchors.right: exitBridgeButton.left; anchors.rightMargin: 14*root.scaleUnit
            anchors.verticalCenter: parent.verticalCenter
            property bool activeHelp: root.firstOrientationActive || bridge.pageHelpActive
            text: activeHelp ? "STOP TUTORIAL" : "TUTORIAL"
            subtext: activeHelp ? "END ORIENTATION" : "FULL GUIDED TOUR"
            accent: root.amber
            danger: false
            stateful: true
            active: activeHelp
            labelScale: .90
            subtextMinSize: Math.max(9,11*root.scaleUnit)
            visible: !root.introVisible
            enabled: true
            opacity: 1.0
            z: 910
            onClicked: { if (activeHelp) root.stopFirstOrientation(); else root.launchLiveOrientation(true) }
            Rectangle {
                anchors.fill: parent
                anchors.margins: -5*root.scaleUnit
                radius: 5*root.scaleUnit
                color: "transparent"
                border.color: root.amber
                border.width: Math.max(2,4*root.scaleUnit)
                visible: pageHelpButton.activeHelp
                opacity: 1.0
                z: 50
                SequentialAnimation on opacity {
                    running: pageHelpButton.activeHelp
                    loops: Animation.Infinite
                    NumberAnimation { to: .28; duration: 560; easing.type:Easing.InOutQuad }
                    NumberAnimation { to: 1.0; duration: 560; easing.type:Easing.InOutQuad }
                }
            }
        }

        Item {
            id: exitBridgeButton
            width: 132*root.scaleUnit; height: 82*root.scaleUnit
            anchors.right: parent.right; anchors.rightMargin: 28*root.scaleUnit
            anchors.verticalCenter: parent.verticalCenter

            // Same shell geometry/material stack as MechanicalButton. Only the
            // emergency-red content/hover accent is different.
            Rectangle {
                x: 3*root.scaleUnit; y: 4*root.scaleUnit
                width: parent.width; height: parent.height
                radius: 3*root.scaleUnit; color: "#000000"; opacity: .72
            }
            Rectangle {
                anchors.fill: parent
                radius: 3*root.scaleUnit
                border.color: "#100f0d"; border.width: 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#5d503f" }
                    GradientStop { position: .16; color: "#352d24" }
                    GradientStop { position: .55; color: "#1a1713" }
                    GradientStop { position: 1.0; color: "#0a0908" }
                }
            }
            Rectangle {
                anchors.fill: parent; anchors.margins: 3*root.scaleUnit
                radius: 2*root.scaleUnit; color: "transparent"
                border.color: exitBridgeMouse.containsMouse ? root.red : "#83745a"
                border.width: exitBridgeMouse.containsMouse ? 2 : 1
            }
            Rectangle {
                x: 8*root.scaleUnit; y: 8*root.scaleUnit
                width: parent.width-16*root.scaleUnit; height: parent.height-16*root.scaleUnit
                radius: 2*root.scaleUnit; color: "#060605"
                border.color: "#050504"; border.width: 2
            }
            Rectangle {
                id: exitBridgeFace
                x: 12*root.scaleUnit; y: (11 + (exitBridgeMouse.pressed ? 2 : 0))*root.scaleUnit
                width: parent.width-24*root.scaleUnit; height: parent.height-24*root.scaleUnit
                radius: 2*root.scaleUnit
                border.color: exitBridgeMouse.containsMouse ? "#a38956" : "#5f594a"
                border.width: 1
                gradient: Gradient {
                    GradientStop { position: 0.0; color: exitBridgeMouse.pressed ? "#181611" : "#3a372d" }
                    GradientStop { position: .10; color: exitBridgeMouse.pressed ? "#1a1812" : "#2e2d25" }
                    GradientStop { position: .56; color: exitBridgeMouse.pressed ? "#151410" : "#23231d" }
                    GradientStop { position: 1.0; color: "#10110d" }
                }
            }
            Rectangle { x:exitBridgeFace.x+2*root.scaleUnit; y:exitBridgeFace.y+2*root.scaleUnit; width:exitBridgeFace.width-4*root.scaleUnit; height:1; color:"#efe0bc"; opacity:exitBridgeMouse.pressed?.08:.22 }
            Rectangle { x:exitBridgeFace.x+2*root.scaleUnit; y:exitBridgeFace.y+exitBridgeFace.height-3*root.scaleUnit; width:exitBridgeFace.width-4*root.scaleUnit; height:2*root.scaleUnit; color:"#000000"; opacity:.66 }
            Rectangle { x:exitBridgeFace.x+2*root.scaleUnit; y:exitBridgeFace.y+exitBridgeFace.height*.48; width:exitBridgeFace.width-4*root.scaleUnit; height:1; color:"#000000"; opacity:.10 }

            Repeater {
                model:[
                    {x:exitBridgeFace.x+5*root.scaleUnit,y:exitBridgeFace.y+5*root.scaleUnit},
                    {x:exitBridgeFace.x+exitBridgeFace.width-11*root.scaleUnit,y:exitBridgeFace.y+5*root.scaleUnit},
                    {x:exitBridgeFace.x+5*root.scaleUnit,y:exitBridgeFace.y+exitBridgeFace.height-11*root.scaleUnit},
                    {x:exitBridgeFace.x+exitBridgeFace.width-11*root.scaleUnit,y:exitBridgeFace.y+exitBridgeFace.height-11*root.scaleUnit}
                ]
                Item {
                    x:modelData.x; y:modelData.y; width:6*root.scaleUnit; height:6*root.scaleUnit
                    Rectangle { anchors.fill:parent; radius:3*root.scaleUnit; color:"#171511"; border.color:"#7f6d4d"; border.width:1; opacity:.60 }
                }
            }

            Rectangle {
                id:exitGlyphWell
                x:exitBridgeFace.x + (exitBridgeFace.width-48*root.scaleUnit)/2
                y:exitBridgeFace.y + 5*root.scaleUnit
                width:48*root.scaleUnit; height:35*root.scaleUnit
                radius:2*root.scaleUnit
                color:"#080706"; border.color:"#5e5646"; border.width:1
                Rectangle {
                    anchors.fill:parent; anchors.margins:3*root.scaleUnit; radius:1*root.scaleUnit
                    color:root.red
                    opacity:exitBridgeMouse.pressed?.55:(exitBridgeMouse.containsMouse?.34:.22)
                }
                Rectangle { anchors.fill:parent; anchors.margins:-4*root.scaleUnit; radius:3*root.scaleUnit; color:root.red; opacity:exitBridgeMouse.containsMouse?.09:.045 }
                Text {
                    anchors.centerIn:parent
                    text:"✕"; color:"#ff574d"
                    font.family:"Consolas"; font.bold:true
                    font.pixelSize:Math.max(22,27*root.scaleUnit)
                }
            }
            Text {
                text:"EXIT"
                color:exitBridgeMouse.containsMouse ? "#fff0e8" : root.red
                font.family:"Consolas"; font.bold:true
                font.pixelSize:Math.max(11,13*root.scaleUnit)
                anchors.horizontalCenter:exitBridgeFace.horizontalCenter
                y:exitBridgeFace.y+exitBridgeFace.height*.69
                height:exitBridgeFace.height*.25
                verticalAlignment:Text.AlignVCenter
            }
            MouseArea {
                id:exitBridgeMouse
                anchors.fill:parent
                hoverEnabled:true
                cursorShape:Qt.PointingHandCursor
                onClicked:root.requestBridgeExit()
            }
            ToolTip {
                visible:exitBridgeMouse.containsMouse
                delay:350
                text:"Exit Bridge\nSave + shut down"
            }
        }

    }

    // Navigation hardware bank.
    MetalPanel {
        id: nav
        x: root.m; y: root.m+root.topH+root.gap
        width: root.navW; height: root.height-y-root.m
        panelColor: "#090a08"; crt: false
        Item {
            id: bridgeModulesGuideTarget
            x: 12*root.scaleUnit; y: 14*root.scaleUnit
            width: parent.width-24*root.scaleUnit
            height: navButtons.y + navButtons.height - y + 12*root.scaleUnit
        }
        SectionTitle { text: "BRIDGE MODULES"; x: 28*root.scaleUnit; y: 23*root.scaleUnit; width: parent.width-56*root.scaleUnit; height: 38*root.scaleUnit }

        Column {
            id: navButtons
            x: 20*root.scaleUnit; y: 76*root.scaleUnit
            width: parent.width-40*root.scaleUnit; spacing: 10*root.scaleUnit
            Repeater {
                id: navModuleRepeater
                // Visual order follows the most common first-run activities. Internal
                // page IDs stay stable so automation and help routing do not change.
                model: [
                    ["OVERVIEW","STATUS + RECORDS","#506454",0],
                    ["COMBAT","THREAT ANALYSIS","#506454",2],
                    ["TRADE","MARKETS & GOODS","#506454",3],
                    ["NAVIGATION","FLIGHT & ROUTE MONITOR","#506454",1],
                    ["COLONIZATION","SYSTEM DEVELOPMENT","#506454",4],
                    ["SETUP","SYSTEM SETTINGS","#506454",8]
                ]
                MechanicalButton {
                    width: navButtons.width; height: Math.max(64,84*root.scaleUnit)
                    text: modelData[0]; subtext: modelData[1]
                    property bool groupedActive: modelData[3]===0 ? (root.currentPage===0 || root.currentPage===5) : (modelData[3]===8 ? (root.currentPage===6 || root.currentPage===7 || root.currentPage===8 || root.currentPage===9 || root.currentPage===10) : modelData[3]===root.currentPage)
                    accent: groupedActive ? root.green : modelData[2]
                    active: groupedActive
                    labelScale: .90; navMode: true
                    onClicked: {
                        root.currentPage = modelData[3]
                        if (modelData[3] === 8) setupScroll.contentY = 0
                        bridge.playUiCue("nav")
                    }
                }
            }
        }

        // Always-visible copilot transcript. It starts below the last module button,
        // so it cannot cover SETUP even at smaller supported window sizes.
        Rectangle {
            id: aiCommsPanel
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: navButtons.bottom; anchors.topMargin: 14*root.scaleUnit
            anchors.bottom: parent.bottom; anchors.bottomMargin: 18*root.scaleUnit
            anchors.leftMargin: 20*root.scaleUnit; anchors.rightMargin: 20*root.scaleUnit
            radius: Math.max(2,3*root.scaleUnit)
            color: "#050907"
            border.color: "#4d493c"
            border.width: 1
            clip: true

            Rectangle { x:5*root.scaleUnit; y:5*root.scaleUnit; width:parent.width-10*root.scaleUnit; height:parent.height-10*root.scaleUnit; color:"transparent"; border.color:"#1d3526"; border.width:1 }

            Text {
                x:12*root.scaleUnit; y:8*root.scaleUnit; width:parent.width-24*root.scaleUnit; height:22*root.scaleUnit
                text:"AI COMMS // "+root.currentUiContextLabel()
                color:root.amber; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(13,16*root.scaleUnit); elide:Text.ElideRight
            }
            Rectangle { x:12*root.scaleUnit; y:34*root.scaleUnit; width:parent.width-24*root.scaleUnit; height:1; color:"#294331"; opacity:.9 }

            ListView {
                id: aiCommsList
                x:12*root.scaleUnit; y:42*root.scaleUnit; width:parent.width-24*root.scaleUnit; height:Math.max(0,parent.height-80*root.scaleUnit)
                clip:true; spacing:5*root.scaleUnit
                model:bridge.aiCommsRows
                onCountChanged: if (count>0) positionViewAtEnd()
                delegate: Item {
                    required property var modelData
                    width:aiCommsList.width
                    height:Math.max(58*root.scaleUnit, commsText.implicitHeight+18*root.scaleUnit)
                    property bool commander:String(modelData.speaker||"").toUpperCase()==="CMDR"
                    Rectangle { anchors.fill:parent; color:commander?"#080d09":"#07110a"; border.color:commander?"#30372f":"#1f4b30"; border.width:1; opacity:.96 }
                    Text { x:8*root.scaleUnit; y:8*root.scaleUnit; width:64*root.scaleUnit; text:commander?"CMDR":"BRIDGE"; color:commander?root.whiteText:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,13*root.scaleUnit) }
                    Text {
                        id:commsText
                        x:74*root.scaleUnit; y:7*root.scaleUnit; width:parent.width-82*root.scaleUnit
                        text:String(modelData.text||""); color:commander?"#c7c1b2":root.whiteText
                        font.family:"Consolas"; font.pixelSize:Math.max(13,15*root.scaleUnit); wrapMode:Text.WordWrap; lineHeight:1.10
                        maximumLineCount: 2; elide: Text.ElideRight
                    }
                }

                Text {
                    anchors.centerIn:parent; visible:aiCommsList.count===0
                    width:parent.width-12*root.scaleUnit
                    text:"HOLD PTT AND ASK THE BRIDGE WHAT YOU WANT TO DO."
                    color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,12.5*root.scaleUnit); wrapMode:Text.WordWrap; horizontalAlignment:Text.AlignHCenter
                }
            }

            Rectangle { x:12*root.scaleUnit; y:parent.height-31*root.scaleUnit; width:parent.width-24*root.scaleUnit; height:1; color:"#294331"; opacity:.9 }
            Rectangle {
                x:12*root.scaleUnit; y:parent.height-23*root.scaleUnit; width:9*root.scaleUnit; height:9*root.scaleUnit; radius:width/2
                color:String(bridge.aiCopilotStatus||"").toUpperCase().indexOf("THINK")>=0?root.amber:root.green
                opacity:.72+.22*Math.sin(bridge.pulse*6.28318)
            }
            Text {
                x:27*root.scaleUnit; y:parent.height-29*root.scaleUnit; width:parent.width-39*root.scaleUnit; height:20*root.scaleUnit
                text:String(bridge.aiCopilotStatus||"READY").toUpperCase()+" // HOLD PTT"
                color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,11*root.scaleUnit); elide:Text.ElideRight
            }
        }
    }

    // Identity readout strip.
    MetalPanel {
        id: identity
        x: nav.x+nav.width+root.gap; y: nav.y
        width: root.width-x-root.m; height: root.infoH
        panelColor: "#07100a"; heavy: false; crt: false
        RowLayout {
            anchors.fill: parent; anchors.margins: 14*root.scaleUnit; spacing: 0
            Repeater {
                model: [
                    ["CMDR",bridge.commander,1.08], ["SHIP",bridge.ship,1.55], ["SYSTEM",bridge.system,1.15],
                    ["STATION",bridge.station,2.35], ["GAME STATE",bridge.gameState,1.42], ["LOCAL",bridge.localTime,1.10]
                ]
                Item {
                    Layout.fillHeight: true; Layout.fillWidth: true; Layout.preferredWidth: modelData[2]*100
                    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: "#284634"; opacity: index===5?0:1 }
                    Text {
                        text: modelData[0]
                        color: "#6f8d79"
                        font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,13*root.scaleUnit)
                        x: 8*root.scaleUnit; y: 4*root.scaleUnit
                    }
                    Text {
                        text: String(modelData[1]).toUpperCase(); color: root.whiteText
                        font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(15,24*root.scaleUnit)
                        x: 8*root.scaleUnit; y: 19*root.scaleUnit; width: parent.width-16*root.scaleUnit; height: parent.height-y-2*root.scaleUnit
                        fontSizeMode: Text.Fit
                        minimumPixelSize: Math.max(11,14*root.scaleUnit)
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight; maximumLineCount: 1; clip: false
                    }
                    MouseArea {
                        anchors.fill:parent
                        visible:index===0
                        hoverEnabled:true
                        cursorShape:Qt.PointingHandCursor
                        onClicked:{root.currentPage=5;bridge.playUiCue("nav")}
                    }
                }
            }
        }
    }

    // LIVE is the home module. Commander records live here as a nested view
    // instead of consuming another main navigation slot.
    Item {
        id: liveSectionTabs
        visible: root.currentPage === 0 || root.currentPage === 5
        x: identity.x; y: identity.y+identity.height+root.gap
        width: identity.width; height: 76*root.scaleUnit
        Row {
            anchors.fill: parent; spacing: 10*root.scaleUnit
            TradeModeButton {
                width:(parent.width-parent.spacing)/2; height:parent.height
                text:"STATUS OVERVIEW"; subtext:"SHIP + BRIDGE STATUS"
                active:root.currentPage===0; accent:root.green; scaleUnit:root.scaleUnit
                onClicked:{root.currentPage=0;bridge.playUiCue("nav")}
            }
            TradeModeButton {
                width:(parent.width-parent.spacing)/2; height:parent.height
                text:"COMMANDER RECORDS"; subtext:"CARGO + SESSION + HISTORY"
                active:root.currentPage===5; accent:root.green; scaleUnit:root.scaleUnit
                onClicked:{root.currentPage=5;bridge.playUiCue("nav")}
            }
        }
    }

    Item {
        id: live
        visible: root.currentPage === 0
        x: identity.x; y: liveSectionTabs.y+liveSectionTabs.height+root.gap
        width: identity.width; height: root.height-y-root.m

        // LEFT: truthful ship telemetry instruments.
        MetalPanel {
            id: shipStatus
            x: 0; y: 0; width: live.width*.255; height: live.height*.565
            panelColor: root.screen
            SectionTitle { text: "SHIP STATUS"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }

            HullGauge {
                x: 28*root.scaleUnit; y: 65*root.scaleUnit
                width: parent.width-56*root.scaleUnit; height: 88*root.scaleUnit
                percent: bridge.hullPercent
            }
            ShieldState {
                x: 28*root.scaleUnit; y: 170*root.scaleUnit
                width: parent.width-56*root.scaleUnit; height: 115*root.scaleUnit
                state: bridge.shieldState; phase: bridge.pulse
            }
            FuelGauge {
                x: 28*root.scaleUnit; y: 298*root.scaleUnit
                width: parent.width-56*root.scaleUnit; height: 82*root.scaleUnit
                percent: bridge.fuelPercent
            }

            Rectangle { x: 28*root.scaleUnit; y: 388*root.scaleUnit; width: parent.width-56*root.scaleUnit; height: 1; color: "#304c38" }
            Text { text: "POWER DISTRIBUTION"; x: 28*root.scaleUnit; y: 404*root.scaleUnit; color: "#94a096"; font.family: "Consolas"; font.pixelSize: Math.max(12,17*root.scaleUnit) }
            Text { text: bridge.pips; anchors.right: parent.right; anchors.rightMargin: 28*root.scaleUnit; y: 404*root.scaleUnit; color: bridge.eliteTelemetryState==="CONNECTED"?root.green:root.muted; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(12,17*root.scaleUnit) }

            Repeater {
                model: [
                    ["CARGO",bridge.cargoText],
                    ["FSD",bridge.fsdState],
                    ["GEAR",bridge.gearState],
                    ["HP",bridge.hardpointsState]
                ]
                Item {
                    x: 28*root.scaleUnit; y: (438+index*30)*root.scaleUnit
                    width: shipStatus.width-56*root.scaleUnit; height: 24*root.scaleUnit
                    Text {
                        text: modelData[0]
                        color: "#94a096"; font.family: "Consolas"
                        font.pixelSize: Math.max(11,14*root.scaleUnit)
                        width: parent.width*.22; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight; clip: true
                    }
                    Text {
                        text: modelData[1]
                        color: (String(modelData[1]).toUpperCase()==="UNKNOWN" || bridge.eliteTelemetryState!=="CONNECTED") ? root.muted : root.green; font.family: "Consolas"; font.bold: true
                        font.pixelSize: Math.max(11,14*root.scaleUnit)
                        x: parent.width*.60; width: parent.width*.26; anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignLeft; elide: Text.ElideRight; clip: true
                    }
                }
            }
        }

        // CENTER: bridge core and ship render display.

        MetalPanel {
            id: bridgeStatus
            x: shipStatus.width+root.gap; y: 0; width: live.width*.43; height: shipStatus.height
            panelColor: root.screen
            SectionTitle { text: "BRIDGE STATUS"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }

            Rectangle {
                id: stateWell
                x: 26*root.scaleUnit; y: 60*root.scaleUnit; width: parent.width-52*root.scaleUnit; height: 82*root.scaleUnit
                color: "#08110b"; border.color: bridge.levelColor(bridge.bridgeLevel); border.width: 1
                Rectangle { anchors.fill: parent; anchors.margins: 4; color: "transparent"; border.color: "#173824"; border.width: 1 }
                Rectangle { width: parent.width * (0.24 + bridge.pulse*0.18); height: 2; x: 12*root.scaleUnit; y: parent.height-8*root.scaleUnit; color: bridge.levelColor(bridge.bridgeLevel); opacity: .28 }
                Text { text: bridge.bridgeState.toUpperCase(); color: bridge.levelColor(bridge.bridgeLevel); font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(30,50*root.scaleUnit); anchors.centerIn: parent }
            }
            Text {
                visible: false
                text: bridge.bridgeMessage.toUpperCase(); color: root.green
                font.family: "Consolas"; font.pixelSize: Math.max(11,15*root.scaleUnit)
                anchors.top: stateWell.bottom; anchors.topMargin: 8*root.scaleUnit; anchors.horizontalCenter: parent.horizontalCenter
            }

            Rectangle {
                id: schematicBay
                x: 26*root.scaleUnit; y: 146*root.scaleUnit
                width: parent.width*.40; height: parent.height-y-64*root.scaleUnit
                color: "#061009"; border.color: "#235f39"; border.width: 2
                clip: true
                Rectangle { anchors.fill: parent; anchors.margins: 2; color: "#020603"; border.color: "#16301f"; border.width: 1 }
                Text {
                    id: frameShipName
                    text: "FRAME // "+((bridge.shipName && bridge.shipName!=="-") ? bridge.shipName : bridge.shipModel).toUpperCase()
                    color: root.green; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(13,21*root.scaleUnit)
                    x: 13*root.scaleUnit; y: 9*root.scaleUnit; width: parent.width-26*root.scaleUnit; height: Math.max(20,26*root.scaleUnit)
                    fontSizeMode: Text.HorizontalFit; minimumPixelSize: Math.max(10,12*root.scaleUnit); elide: Text.ElideRight; maximumLineCount: 1
                }
                Text {
                    visible: bridge.shipName && bridge.shipName!=="-" && bridge.shipModel && bridge.shipModel!=="-"
                    text: bridge.shipModel.toUpperCase()
                    color: "#8bb79a"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(11,15*root.scaleUnit)
                    x: 13*root.scaleUnit; y: frameShipName.y+frameShipName.height-2*root.scaleUnit; width: parent.width-26*root.scaleUnit; height: Math.max(16,20*root.scaleUnit)
                    fontSizeMode: Text.HorizontalFit; minimumPixelSize: Math.max(9,11*root.scaleUnit); elide: Text.ElideRight; maximumLineCount: 1
                }
                Item {
                    id: shipArtViewport
                    x: 10*root.scaleUnit
                    y: (bridge.shipName && bridge.shipName!=="-") ? 62*root.scaleUnit : 46*root.scaleUnit
                    width: parent.width-20*root.scaleUnit
                    height: parent.height-y-10*root.scaleUnit
                    clip: true
                    Image {
                        id: shipCard
                        anchors.fill: parent
                        anchors.margins: 2*root.scaleUnit
                        source: root.shipArtSource(bridge.shipModel)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        opacity: 0.96
                        scale: 1.14
                    }
                    ScanGrid { anchors.fill: parent; opacity: .14; step: Math.max(20,28*root.scaleUnit) }
                    Rectangle { anchors.fill: parent; color: "transparent"; border.color: "#2adf81"; border.width: 1; opacity: .22 }
                    Rectangle {
                        width: parent.width * 0.92; height: Math.max(2, 3*root.scaleUnit)
                        x: parent.width*0.04
                        y: ((parent.height-height) * bridge.pulse)
                        color: root.green
                        opacity: 0.10
                    }
                }
            }

            Column {
                id: bridgeStatusRows
                x: schematicBay.x+schematicBay.width+26*root.scaleUnit; y: 144*root.scaleUnit
                width: parent.width-x-24*root.scaleUnit
                height: parent.height-y-18*root.scaleUnit
                spacing: Math.max(2,4*root.scaleUnit)
                property real fittedRowHeight: bridge.systemRows.length > 0
                    ? (height - spacing*Math.max(0, bridge.systemRows.length-1)) / bridge.systemRows.length
                    : height
                Repeater {
                    model: bridge.systemRows
                    StatusLamp {
                        width: parent.width; height: bridgeStatusRows.fittedRowHeight
                        label: modelData.label; value: modelData.value
                        stateColor: bridge.levelColor(modelData.level)
                        pulse: modelData.value === "THINKING" || modelData.value === "LISTENING"
                        phase: bridge.pulse; fontScale: 1.34
                    }
                }
            }
        }

        // RIGHT: event recorder and alerts.
        Column {
            id: rightStack
            x: bridgeStatus.x+bridgeStatus.width+root.gap; y: 0
            width: live.width-x; spacing: root.gap
            MetalPanel {
                width: parent.width; height: shipStatus.height*.64; panelColor: root.screen
                SectionTitle { text: "RECENT EVENTS"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }
                Rectangle {
                    width: parent.width*0.22; height: 2
                    x: 24*root.scaleUnit + (parent.width*0.62)*bridge.pulse
                    y: 56*root.scaleUnit
                    color: root.green; opacity: .14
                }
                Text {
                    visible: bridge.recentEvents.length === 0
                    text: bridge.connected ? "WAITING FOR JOURNAL EVENTS" : "STARTING BRIDGE SYSTEMS"
                    x: 28*root.scaleUnit; y: 92*root.scaleUnit; width: parent.width-56*root.scaleUnit
                    color: "#526258"; font.family: "Consolas"; font.pixelSize: Math.max(11,14*root.scaleUnit)
                    horizontalAlignment: Text.AlignHCenter
                }
                Column {
                    x: 28*root.scaleUnit; y: 67*root.scaleUnit; width: parent.width-56*root.scaleUnit
                    spacing: Math.max(2, 4*root.scaleUnit)
                    Repeater {
                        model: bridge.recentEvents
                        Item {
                            width: parent.width; height: Math.max(36, 50*root.scaleUnit)
                            clip: true
                            readonly property real eventDotSize: Math.max(4, 5*root.scaleUnit)
                            readonly property real eventTimeX: Math.max(14, 18*root.scaleUnit)
                            readonly property real eventTimeWidth: Math.max(96, 138*root.scaleUnit)
                            readonly property real eventGap: Math.max(8, 10*root.scaleUnit)
                            readonly property real eventRightPadding: Math.max(10, 14*root.scaleUnit)
                            readonly property real eventTextX: eventTimeX + eventTimeWidth + eventGap
                            readonly property real eventTextWidth: Math.max(0, width - eventTextX - eventRightPadding)
                            readonly property real eventSummaryWidth: Math.max(0, width - eventTimeX - eventRightPadding)
                            Rectangle {
                                width: parent.eventDotSize; height: parent.eventDotSize; radius: width/2
                                color: index===0?root.green:"#486052"
                                opacity: index===0 ? (.68 + .32*Math.sin(bridge.pulse*6.28318)) : 1
                                anchors.left: parent.left
                                y: Math.max(5, 8*root.scaleUnit)
                            }
                            Text {
                                text: "["+modelData.time+"]"
                                color: "#728178"; font.family: "Consolas"; font.pixelSize: Math.max(13,18*root.scaleUnit)
                                x: parent.eventTimeX; y: 0; width: parent.eventTimeWidth; height: parent.height*.48
                                elide: Text.ElideRight; clip: true; wrapMode: Text.NoWrap
                                verticalAlignment: Text.AlignVCenter
                            }
                            Text {
                                text: modelData.event ? modelData.event : modelData.text
                                color: index===0?root.whiteText:"#aeb8ae"; font.family: "Consolas"; font.pixelSize: Math.max(13,18*root.scaleUnit)
                                x: parent.eventTextX; y: 0; width: parent.eventTextWidth; height: parent.height*.48
                                elide: Text.ElideRight; clip: true; wrapMode: Text.NoWrap
                                verticalAlignment: Text.AlignVCenter
                            }
                            Text {
                                text: modelData.summary ? modelData.summary : ""
                                color: index===0?"#91aa98":"#68766d"; font.family: "Consolas"; font.pixelSize: Math.max(12,16*root.scaleUnit)
                                x: parent.eventTimeX; y: parent.height*.46; width: parent.eventSummaryWidth; height: parent.height*.50
                                elide: Text.ElideRight; clip: true; wrapMode: Text.NoWrap
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }
            }
            MetalPanel {
                width: parent.width; height: shipStatus.height-parent.children[0].height-root.gap; panelColor: root.screen
                SectionTitle { text: "ALERTS"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }
                StatusLamp { x: 28*root.scaleUnit; y: 69*root.scaleUnit; width: parent.width-56*root.scaleUnit; height: 38*root.scaleUnit; label: bridge.alertLabel; value: bridge.alertValue; stateColor: bridge.levelColor(bridge.alertLevel); pulse: bridge.alertLevel === "bad"; phase: bridge.pulse }
                Text { text: bridge.alertDetail; color: bridge.levelColor(bridge.alertLevel); opacity: .70; font.family: "Consolas"; font.pixelSize: Math.max(10,13*root.scaleUnit); x: 30*root.scaleUnit; y: 126*root.scaleUnit; width: parent.width-60*root.scaleUnit; elide: Text.ElideRight }
            }
        }

        Row {
            id: bottomRow
            x: 0; y: shipStatus.height+root.gap; width: live.width; height: live.height-y; spacing: root.gap

            MetalPanel {
                width: bottomRow.width*.31; height: bottomRow.height; panelColor: root.screen
                SectionTitle { text: "CURRENT DESTINATION"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }
                Reticle { x: 28*root.scaleUnit; y: 77*root.scaleUnit; width: 112*root.scaleUnit; height: 112*root.scaleUnit; color: root.green; phase: bridge.pulse }
                Text { text: bridge.destination; color: root.green; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(22,34*root.scaleUnit); x: 158*root.scaleUnit; y: 81*root.scaleUnit; width: parent.width-x-24*root.scaleUnit; elide: Text.ElideRight }
                Text { text: "FSD TARGET: " + bridge.fsdTarget; color: "#abb4a9"; font.family: "Consolas"; font.pixelSize: Math.max(11,15*root.scaleUnit); x: 160*root.scaleUnit; y: 130*root.scaleUnit; width: parent.width-x-24*root.scaleUnit; elide: Text.ElideRight }
                Text { text: bridge.routeStatus; color: "#66806e"; font.family: "Consolas"; font.pixelSize: Math.max(12,15*root.scaleUnit); x: 160*root.scaleUnit; y: 160*root.scaleUnit; width: parent.width-x-24*root.scaleUnit; elide: Text.ElideRight }
                Rectangle { x: 28*root.scaleUnit; y: 215*root.scaleUnit; width: parent.width-56*root.scaleUnit; height: 1; color: "#294331" }
                Text { text: "NEXT STAR"; x: 30*root.scaleUnit; y: 238*root.scaleUnit; color: "#718178"; font.family: "Consolas"; font.pixelSize: Math.max(11,14*root.scaleUnit) }
                Text { text: bridge.nextStarText; anchors.right: parent.right; anchors.rightMargin: 30*root.scaleUnit; y: 238*root.scaleUnit; color: root.whiteText; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,13*root.scaleUnit) }
            }

            MetalPanel {
                width: bottomRow.width*.21; height: bottomRow.height; panelColor: root.screen
                SectionTitle { text: "VOICE / AI"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }
                VoiceWave { x: 28*root.scaleUnit; y: 72*root.scaleUnit; width: parent.width-56*root.scaleUnit; height: 86*root.scaleUnit; color: root.green; activeColor: root.amber; phase: bridge.pulse; speaking: bridge.voiceMode=="SPEAKING"; listening: bridge.voiceMode=="LISTENING" }
                StatusLamp { x: 30*root.scaleUnit; y: 173*root.scaleUnit; width: parent.width-60*root.scaleUnit; height: 36*root.scaleUnit; label: "PTT"; value: bridge.pttStatus; stateColor: bridge.pttStatus === "NOT MAPPED" ? root.red : root.green; pulse: bridge.voiceMode==="LISTENING"; phase: bridge.pulse }
                StatusLamp { x: 30*root.scaleUnit; y: 217*root.scaleUnit; width: parent.width-60*root.scaleUnit; height: 36*root.scaleUnit; label: "AI / VOICE"; value: bridge.lunaStatus; stateColor: bridge.lunaStatus === "NO KEY" ? root.red : ((bridge.lunaStatus === "THINKING" || bridge.lunaStatus === "TALKING") ? root.amber : root.green); pulse: bridge.lunaStatus === "THINKING" || bridge.lunaStatus === "TALKING"; phase: bridge.pulse }
                Text { text: bridge.voiceMode==="SPEAKING" ? "SPEAKING" : (bridge.voiceMode==="LISTENING" ? "LISTENING" : "VOICE READY"); x: 31*root.scaleUnit; y: 274*root.scaleUnit; color: bridge.voiceMode==="SPEAKING" ? root.amber : (bridge.voiceMode==="LISTENING" ? root.green : "#5e7465"); font.family: "Consolas"; font.pixelSize: Math.max(11,14*root.scaleUnit) }
                Row {
                    x: 30*root.scaleUnit; y: 304*root.scaleUnit; spacing: 5*root.scaleUnit
                    Repeater {
                        model: 8
                        Rectangle {
                            width: 8*root.scaleUnit; height: bridge.voiceMode=="SPEAKING"
                                ? 14*root.scaleUnit + ((index+Math.floor(bridge.pulse*18))%5)*5*root.scaleUnit
                                : 12*root.scaleUnit + ((index+Math.floor(bridge.pulse*8))%3)*4*root.scaleUnit
                            color: bridge.voiceMode=="SPEAKING" ? root.amber : (index < 3 ? root.dimGreen : "#122016")
                            opacity: bridge.voiceMode=="SPEAKING" ? (0.72 + 0.22*Math.sin((bridge.pulse*12.56636)+index)) : .75
                        }
                    }
                }
            }

            MetalPanel {
                width: bottomRow.width*.19; height: bottomRow.height; panelColor: root.screen
                SectionTitle { text: "AI USAGE"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }
                Text { text: "SESSION"; x: 28*root.scaleUnit; y: 78*root.scaleUnit; color: "#718178"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(13,17*root.scaleUnit) }
                Text { text: "REQUESTS\nINPUT TOKENS\nOUTPUT TOKENS\nEST. COST"; x: 28*root.scaleUnit; y: 117*root.scaleUnit; color: "#9aa59b"; font.family: "Consolas"; font.pixelSize: Math.max(13,16*root.scaleUnit); lineHeight: 1.7 }
                Text { text: bridge.aiCalls + "\n" + bridge.aiInputTokens + "\n" + bridge.aiOutputTokens + "\n" + bridge.aiEstimatedCostText; anchors.right: parent.right; anchors.rightMargin: 30*root.scaleUnit; y: 117*root.scaleUnit; color: root.whiteText; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(13,16*root.scaleUnit); lineHeight: 1.7; horizontalAlignment: Text.AlignRight }
                Row {
                    x: 28*root.scaleUnit; y: 252*root.scaleUnit; spacing: 7*root.scaleUnit
                    Repeater { model: 12; Rectangle { width: 10*root.scaleUnit; height: 28*root.scaleUnit; color: index<bridge.aiMeterSegments?root.dimGreen:"#0d1710"; border.color: "#1d3424"; border.width: 1 } }
                }
            }

            MetalPanel {
                width: bottomRow.width-bottomRow.children[0].width-bottomRow.children[1].width-bottomRow.children[2].width-root.gap*3
                height: bottomRow.height; panelColor: root.screen
                SectionTitle { text: "QUICK ACTIONS"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }
                Grid {
                    x: 20*root.scaleUnit; y: 66*root.scaleUnit
                    width: parent.width-40*root.scaleUnit; height: parent.height-88*root.scaleUnit
                    columns: 2; rows: 2; columnSpacing: 10*root.scaleUnit; rowSpacing: 10*root.scaleUnit
                    MechanicalButton { enabled:bridge.eliteControlsReady; opacity:enabled?1:.45; width: (parent.width-parent.columnSpacing)/2; height: (parent.height-parent.rowSpacing)/2; text: "DOCK"; subtext: enabled?"REQUEST DOCKING":"ELITE BINDS REQUIRED"; accent: root.green; labelScale: .82; onClicked: bridge.requestCommand("dock") }
                    MechanicalButton { enabled:bridge.eliteControlsReady; opacity:enabled?1:.45; width: (parent.width-parent.columnSpacing)/2; height: (parent.height-parent.rowSpacing)/2; text: "LAUNCH"; subtext: enabled?"TAKE OFF":"ELITE BINDS REQUIRED"; accent: root.amber; labelScale: .82; onClicked: bridge.requestCommand("launch") }
                    MechanicalButton { enabled:bridge.eliteControlsReady; opacity:enabled?1:.45; width: (parent.width-parent.columnSpacing)/2; height: (parent.height-parent.rowSpacing)/2; text: "CLEAR + JUMP"; subtext: enabled?"EXIT MASS LOCK":"ELITE BINDS REQUIRED"; accent: root.amber; labelScale: .62; onClicked: bridge.requestCommand("clear") }
                    MechanicalButton { width: (parent.width-parent.columnSpacing)/2; height: (parent.height-parent.rowSpacing)/2; text: "CANCEL"; subtext: "ABORT AUTOMATION"; accent: root.red; danger:true; labelScale: .80; onClicked: bridge.requestCommand("cancel") }
                }
            }
        }
    }

    // NAVIGATION MODULE: real .95 route state + proven Galaxy Map plotting engine.
    Item {
        id: navigationPage
        visible: root.currentPage === 1
        x: identity.x
        y: identity.y + identity.height + root.gap
        width: identity.width
        height: root.height - y - root.m
        property string navDraft: ""
        property string navSelectedCandidate: ""
        property string lastLiveDestination: ""
        property bool navDraftDirty: false
        readonly property bool showOrientationDemo: root.firstOrientationActive && root.currentPage === 1
        readonly property var demoWaypoints: [
            {system:"EGA", kind:"CURRENT", scoopable:true},
            {system:"LTT 15449", scoopable:true},
            {system:"HR 4979", scoopable:false},
            {system:"SHENVE", scoopable:true},
            {system:"WISE 1506+7027", scoopable:null},
            {system:"HIP 20277", scoopable:true},
            {kind:"ELLIPSIS", hiddenCount:4},
            {system:"ROSS 154", scoopable:true},
            {system:"SHINRARTA DEZHRA", kind:"DESTINATION", scoopable:true}
        ]

        Component.onCompleted: {
            navDraft = bridge.navDestinationInput
            lastLiveDestination = bridge.navDestinationInput
        }
        Connections {
            target: bridge
            function onStateChanged() {
                var live = bridge.navDestinationInput
                if (live !== navigationPage.lastLiveDestination && !navDestinationInput.activeFocus) {
                    navigationPage.lastLiveDestination = live
                    navigationPage.navDraft = live
                    navigationPage.navDraftDirty = false
                    navigationPage.navSelectedCandidate = ""
                }
            }
        }

        Timer {
            id: navSuggestionTimer
            interval: 350
            repeat: false
            onTriggered: bridge.requestSystemSuggestions(navigationPage.navDraft)
        }

        Row {
            id: navTop
            width: parent.width
            height: parent.height * .61
            spacing: root.gap

            MetalPanel {
                width: navTop.width * .58
                height: navTop.height
                panelColor: root.screen
                SectionTitle { text: "ROUTE COMPUTER"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }

                RouteDisplay {
                    id: routeDisplay
                    width: parent.width * .82
                    height: parent.height - 190*root.scaleUnit
                    x: (parent.width-width)/2
                    y: 70*root.scaleUnit
                    phase: bridge.pulse
                    green: root.green; dimGreen: root.dimGreen; amber: root.amber
                    textScale: Math.max(1.0, 1.15*root.scaleUnit)
                    origin: navigationPage.showOrientationDemo ? "EGA" : bridge.system
                    destination: navigationPage.showOrientationDemo ? "SHINRARTA DEZHRA" : bridge.destination
                    inSystemTargetVisible: navigationPage.showOrientationDemo ? false : bridge.navInSystemTargetVisible
                    inSystemTargetName: navigationPage.showOrientationDemo ? "-" : bridge.navInSystemTargetName
                    inSystemTargetKind: navigationPage.showOrientationDemo ? "IN-SYSTEM TARGET" : bridge.navInSystemTargetKind
                    inSystemTargetConfirmedStation: navigationPage.showOrientationDemo ? false : bridge.navInSystemTargetConfirmedStation
                    waypoints: navigationPage.showOrientationDemo ? navigationPage.demoWaypoints : bridge.navRouteEntries
                }

                Row {
                    x: 28*root.scaleUnit; y: parent.height-72*root.scaleUnit
                    width: parent.width-56*root.scaleUnit; height: 48*root.scaleUnit; spacing: 20*root.scaleUnit
                    Repeater {
                        model: [
                            ["ROUTE",navigationPage.showOrientationDemo?"ACTIVE":bridge.navRouteState,navigationPage.showOrientationDemo?root.green:(bridge.navArmed?root.green:root.red)],
                            ["JUMPS",navigationPage.showOrientationDemo?"12":bridge.navJumpsText,navigationPage.showOrientationDemo?root.green:(bridge.routeJumps>=0?root.green:"#718178")],
                            ["FSD",navigationPage.showOrientationDemo?"READY":bridge.fsdState,navigationPage.showOrientationDemo?root.green:(bridge.fsdState==="MASS LOCKED"?root.red:root.green)],
                            ["MASS LOCK",navigationPage.showOrientationDemo?"CLEAR":bridge.navMassLock,navigationPage.showOrientationDemo?root.green:bridge.levelColor(bridge.navMassLockLevel)],
                            ["NEXT STAR",navigationPage.showOrientationDemo?"K-CLASS":(bridge.nextStarClass==="-"?"UNKNOWN":bridge.nextStarClass+"-CLASS"),navigationPage.showOrientationDemo?root.amber:((bridge.nextStarScoopableKnown && !bridge.nextStarScoopable)?root.red:root.amber)]
                        ]
                        Item {
                            width: (parent.width-parent.spacing*4)/5; height: parent.height
                            Text { text: modelData[0]; color: "#718178"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(12,15*root.scaleUnit); anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter }
                            Text { text: modelData[1]; color: modelData[2]; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(14,19*root.scaleUnit); fontSizeMode: Text.Fit; minimumPixelSize: Math.max(10,12*root.scaleUnit); anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; width: parent.width; height: Math.max(22,27*root.scaleUnit); horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                        }
                    }
                }
            }

            Column {
                width: navTop.width - navTop.children[0].width - root.gap
                height: navTop.height
                spacing: root.gap

                MetalPanel {
                    width: parent.width; height: (parent.height-root.gap)*.50
                    panelColor: root.screen
                    SectionTitle { text: "JUMP STATUS"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }
                    Column {
                        x: 28*root.scaleUnit; y: 70*root.scaleUnit; width: parent.width-56*root.scaleUnit; spacing: 9*root.scaleUnit
                        Repeater {
                            model: [
                                ["CURRENT SYSTEM",navigationPage.showOrientationDemo?"EGA":bridge.system,root.whiteText],
                                ["DESTINATION",navigationPage.showOrientationDemo?"SHINRARTA DEZHRA":(bridge.navInSystemTargetVisible?bridge.navInSystemTargetName:bridge.destination),navigationPage.showOrientationDemo?root.green:(bridge.navInSystemTargetVisible?root.amber:(bridge.navRouteValid?root.green:root.amber))],
                                ["NEXT JUMP",navigationPage.showOrientationDemo?"LTT 15449":bridge.fsdTarget,navigationPage.showOrientationDemo?root.green:(bridge.fsdTarget!=="-"?root.green:"#718178")],
                                ["STAR CLASS",navigationPage.showOrientationDemo?"K-CLASS // SCOOPABLE":bridge.nextStarText,navigationPage.showOrientationDemo?root.amber:((bridge.nextStarScoopableKnown && !bridge.nextStarScoopable)?root.red:root.amber)],
                                ["FRAME SHIFT DRIVE",navigationPage.showOrientationDemo?"READY":bridge.fsdState,navigationPage.showOrientationDemo?root.green:(bridge.fsdState==="MASS LOCKED"?root.red:root.green)],
                                ["MASS LOCK",navigationPage.showOrientationDemo?"CLEAR":bridge.navMassLock,navigationPage.showOrientationDemo?root.green:bridge.levelColor(bridge.navMassLockLevel)]
                            ]
                            Item {
                                width: parent.width; height: 33*root.scaleUnit
                                Text { text: modelData[0]; color: "#839084"; font.family: "Consolas"; font.pixelSize: Math.max(15,20*root.scaleUnit); anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: String(modelData[1]).toUpperCase(); color: modelData[2]; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(16,22*root.scaleUnit); anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: parent.width*.60; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
                            }
                        }
                    }
                }

                MetalPanel {
                    width: parent.width; height: parent.height-parent.children[0].height-root.gap
                    panelColor: root.screen
                    SectionTitle { text: "NAV COMPUTER"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }

                    Text { text: "DESTINATION SYSTEM"; x: 28*root.scaleUnit; y: 66*root.scaleUnit; color: "#718178"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(13,17*root.scaleUnit) }
                    Text { text: bridge.navSuggestionStatus; anchors.right: parent.right; anchors.rightMargin: 28*root.scaleUnit; y: 66*root.scaleUnit; color: "#607765"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(12,15*root.scaleUnit); width: parent.width*.47; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
                    Rectangle {
                        x: 28*root.scaleUnit; y: 91*root.scaleUnit; width: parent.width-56*root.scaleUnit; height: 62*root.scaleUnit
                        color: "#061008"; border.color: navDestinationInput.activeFocus ? root.green : "#244a30"; border.width: 1
                        TextInput {
                            id: navDestinationInput
                            text: navigationPage.navDraft
                            color: root.green; selectionColor: root.dimGreen; selectedTextColor: root.whiteText
                            font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(20,31*root.scaleUnit)
                            x: 14*root.scaleUnit; y: 8*root.scaleUnit; width: parent.width-28*root.scaleUnit; height: parent.height-16*root.scaleUnit
                            verticalAlignment: TextInput.AlignVCenter; clip: true; selectByMouse: true
                            onTextEdited: { navigationPage.navDraft = text; navigationPage.navDraftDirty = true; navigationPage.navSelectedCandidate = ""; navSuggestionTimer.restart() }
                            Keys.onReturnPressed: {
                                var candidate = bridge.navSystemSuggestions.length>0 ? String(bridge.navSystemSuggestions[0]) : String(navigationPage.navDraft).trim()
                                navigationPage.navSelectedCandidate = candidate
                                navigationPage.navDraft = candidate
                                bridge.requestSystemSuggestions("")
                            }
                            Keys.onEnterPressed: {
                                var candidate = bridge.navSystemSuggestions.length>0 ? String(bridge.navSystemSuggestions[0]) : String(navigationPage.navDraft).trim()
                                navigationPage.navSelectedCandidate = candidate
                                navigationPage.navDraft = candidate
                                bridge.requestSystemSuggestions("")
                            }
                        }
                        Rectangle { width: 9*root.scaleUnit; height: width; radius: width/2; color: bridge.navRouteValid?root.green:root.amber; anchors.right: parent.right; anchors.rightMargin: 14*root.scaleUnit; anchors.verticalCenter: parent.verticalCenter; opacity: .58+.32*Math.sin(bridge.pulse*6.28318) }
                    }
                    Rectangle {
                        visible: navDestinationInput.activeFocus && bridge.navSystemSuggestions.length > 0
                        x: 28*root.scaleUnit; y: 154*root.scaleUnit; z: 20
                        width: parent.width-56*root.scaleUnit
                        height: bridge.navSystemSuggestions.length * Math.max(28,34*root.scaleUnit)
                        color: "#071009"; border.color: "#315b3a"; border.width: 1
                        Column {
                            anchors.fill: parent
                            Repeater {
                                model: bridge.navSystemSuggestions
                                Rectangle {
                                    width: parent.width; height: Math.max(28,34*root.scaleUnit)
                                    color: suggestionMouse.containsMouse ? "#102619" : (index%2===0 ? "#08130c" : "#071009")
                                    border.color: "#17291c"; border.width: 1
                                    Text { text: modelData; x: 12*root.scaleUnit; width: parent.width-24*root.scaleUnit; anchors.verticalCenter: parent.verticalCenter; color: suggestionMouse.containsMouse?root.whiteText:root.green; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(13,17*root.scaleUnit); elide: Text.ElideRight }
                                    MouseArea {
                                        id: suggestionMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { navigationPage.navDraft=String(modelData); navigationPage.navSelectedCandidate=String(modelData); navigationPage.navDraftDirty=true; navDestinationInput.forceActiveFocus(); navDestinationInput.cursorPosition=navigationPage.navDraft.length; bridge.requestSystemSuggestions("") }
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        text: navigationPage.showOrientationDemo
                            ? "ROUTE DATA VALID  //  12 JUMPS  //  ORIENTATION DEMO ROUTE"
                            : (navigationPage.navSelectedCandidate!==""
                                ? ("DESTINATION SELECTED // "+navigationPage.navSelectedCandidate.toUpperCase()+" // PRESS PLOT ROUTE")
                                : (bridge.navRouteValid
                                    ? ("ACTIVE ROUTE // "+bridge.navJumpsText+" JUMP"+(bridge.routeJumps===1?"":"S")+" // "+bridge.navRouteSource.toUpperCase())
                                    : (bridge.navArmed ? "NAVIGATION READY // TYPE A SYSTEM, SELECT IT, THEN PLOT" : "NAVIGATION OFF")))
                        x: 30*root.scaleUnit; y: 166*root.scaleUnit; width: parent.width-60*root.scaleUnit
                        color: bridge.navRouteValid?"#6c8974":root.amber; font.family: "Consolas"; font.pixelSize: Math.max(13,17*root.scaleUnit); elide: Text.ElideRight
                    }
                    Rectangle { x: 28*root.scaleUnit; y: 199*root.scaleUnit; width: parent.width-56*root.scaleUnit; height: 1; color: "#294331" }
                    Text {
                        text: (navigationPage.showOrientationDemo?"ROUTE LIVE  //  MIXED SCOOPABLE STARS  //  DYNAMIC LABELS + COMPRESSED JUMPS":bridge.navStatus.toUpperCase()); x: 30*root.scaleUnit; y: 216*root.scaleUnit; width: parent.width-60*root.scaleUnit; height: parent.height-y-18*root.scaleUnit
                        color: navigationPage.showOrientationDemo?root.green:(bridge.navArmed?root.green:root.red); font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(13,18*root.scaleUnit)
                        wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                    }
                }
            }
        }

        Row {
            id: navBottom
            x: 0; y: navTop.height + root.gap
            width: parent.width; height: parent.height-y; spacing: root.gap

            MetalPanel {
                width: navBottom.width*.34; height: navBottom.height; panelColor: root.screen
                SectionTitle { text: "FLIGHT PLAN"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }
                Column {
                    x: 28*root.scaleUnit; y: 68*root.scaleUnit; width: parent.width-56*root.scaleUnit; spacing: 9*root.scaleUnit
                    Repeater {
                        model: bridge.navFlightPlan
                        Rectangle {
                            width: parent.width; height: 55*root.scaleUnit
                            color: modelData.level==="ok" ? "#07160d" : "#080a08"
                            border.color: modelData.level==="ok" ? "#245838" : (modelData.level==="warn"?"#6b5428":"#222b24"); border.width: 1
                            Text { text: modelData.step; x: 12*root.scaleUnit; anchors.verticalCenter: parent.verticalCenter; color: root.amber; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(16,21*root.scaleUnit) }
                            Text { text: modelData.text; x: 54*root.scaleUnit; anchors.verticalCenter: parent.verticalCenter; color: bridge.levelColor(modelData.level); font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(14,19*root.scaleUnit); width: parent.width-66*root.scaleUnit; elide: Text.ElideRight }
                        }
                    }
                }
            }

            MetalPanel {
                width: navBottom.width*.31; height: navBottom.height; panelColor: root.screen
                SectionTitle { text: "ROUTE LOG"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }
                Text {
                    visible: bridge.navHistory.length===0
                    text: "WAITING FOR TRAVEL / NAVIGATION EVENTS"; x: 28*root.scaleUnit; y: 90*root.scaleUnit; width: parent.width-56*root.scaleUnit
                    color: "#526258"; font.family: "Consolas"; font.pixelSize: Math.max(13,17*root.scaleUnit); horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
                Item {
                    id: routeLogViewport
                    x: 28*root.scaleUnit; y: 66*root.scaleUnit; width: parent.width-56*root.scaleUnit
                    height: flightOpsTitle.y-y-8*root.scaleUnit; clip: true
                    Column {
                        width: parent.width; spacing: 8*root.scaleUnit
                        Repeater {
                            model: bridge.navHistory
                            Item {
                                width: parent.width; height: Math.max(43,50*root.scaleUnit); clip: true
                                Rectangle { width: 6*root.scaleUnit; height: width; radius: width/2; color: index===0?root.green:"#43604c"; anchors.left: parent.left; anchors.top: parent.top; anchors.topMargin: 9*root.scaleUnit }
                                Text { text: "["+modelData.time+"]"; x: 19*root.scaleUnit; width: 112*root.scaleUnit; color: "#78877d"; font.family: "Consolas"; font.pixelSize: Math.max(12,16*root.scaleUnit); anchors.top: parent.top; anchors.topMargin: 1*root.scaleUnit; elide: Text.ElideRight }
                                Text {
                                    text: modelData.text; x: 138*root.scaleUnit; y: 0
                                    color: index===0?root.whiteText:"#b4bdb6"; font.family: "Consolas"; font.pixelSize: Math.max(13,17*root.scaleUnit)
                                    width: parent.width-x; height: parent.height
                                    wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
                Text {
                    id: flightOpsTitle
                    text: "FLIGHT OPS"
                    x: 28*root.scaleUnit; y: parent.height-Math.max(108,126*root.scaleUnit)
                    width: parent.width-56*root.scaleUnit; height: Math.max(18,22*root.scaleUnit)
                    color: "#8a978d"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(13,17*root.scaleUnit); horizontalAlignment: Text.AlignHCenter
                }
                Row {
                    id: flightOpsHelp
                    x: 28*root.scaleUnit; y: flightOpsTitle.y+flightOpsTitle.height+2*root.scaleUnit
                    width: parent.width-56*root.scaleUnit; height: Math.max(16,20*root.scaleUnit); spacing: 8*root.scaleUnit
                    Text { width: (parent.width-parent.spacing)/2; text: "REQUEST DOCKING"; color: "#7e8c82"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,12*root.scaleUnit); horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
                    Text { width: (parent.width-parent.spacing)/2; text: "LEAVE STATION"; color: "#7e8c82"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,12*root.scaleUnit); horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
                }
                Row {
                    id: flightOpsRow
                    x: 28*root.scaleUnit; y: parent.height-height-9*root.scaleUnit
                    width: parent.width-56*root.scaleUnit; height: Math.max(48,68*root.scaleUnit); spacing: 8*root.scaleUnit
                    MechanicalButton { enabled:bridge.eliteControlsReady; opacity:enabled?1:.45; width: (parent.width-parent.spacing)/2; height: parent.height; text: "DOCK"; subtext:enabled?"":"ELITE BINDS REQUIRED"; accent: root.green; labelScale: .95; onClicked: bridge.requestCommand("dock") }
                    MechanicalButton { enabled:bridge.eliteControlsReady; opacity:enabled?1:.45; width: (parent.width-parent.spacing)/2; height: parent.height; text: "LAUNCH"; subtext:enabled?"":"ELITE BINDS REQUIRED"; accent: root.amber; labelScale: .91; onClicked: bridge.requestCommand("launch") }
                }
            }

            MetalPanel {
                width: navBottom.width - navBottom.children[0].width - navBottom.children[1].width - root.gap*2
                height: navBottom.height; panelColor: root.screen
                SectionTitle { text: "NAV ACTIONS"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }
                Grid {
                    x: 20*root.scaleUnit; y: 66*root.scaleUnit
                    width: parent.width-40*root.scaleUnit; height: parent.height-y-Math.max(54,96*root.scaleUnit)
                    columns: 3; rows: 2; columnSpacing: 8*root.scaleUnit; rowSpacing: 8*root.scaleUnit
                    Item { width:(parent.width-parent.columnSpacing*2)/3; height:(parent.height-parent.rowSpacing)/2
                        MechanicalButton { anchors.fill:parent; enabled:bridge.eliteControlsReady; opacity:enabled?1:.45; text:"PLOT ROUTE"; subtext:!enabled?"ELITE BINDS REQUIRED":(navigationPage.navSelectedCandidate!==""?"PLOT SELECTED DESTINATION":"TARGET FIELD"); accent:root.green; labelScale:.62; onClicked:{ var target=navigationPage.navSelectedCandidate!==""?navigationPage.navSelectedCandidate:navigationPage.navDraft; bridge.plotRoute(target); navigationPage.navDraftDirty=false; navigationPage.navSelectedCandidate="" } }
                        Rectangle { anchors.fill:parent; anchors.margins:-4*root.scaleUnit; visible:navigationPage.navSelectedCandidate!==""; color:"transparent"; border.color:root.amber; border.width:Math.max(2,3*root.scaleUnit); SequentialAnimation on opacity { running:parent.visible; loops:Animation.Infinite; NumberAnimation{to:.28;duration:420}
                            NumberAnimation{to:1;duration:420} } }
                    }
                    MechanicalButton { enabled:bridge.eliteControlsReady; opacity:enabled?1:.45; width: (parent.width-parent.columnSpacing*2)/3; height: (parent.height-parent.rowSpacing)/2; text: "CLEAR + JUMP"; subtext: enabled?"EXIT MASS LOCK":"ELITE BINDS REQUIRED"; accent: root.amber; labelScale: .48; onClicked: bridge.requestCommand("clear") }
                    MechanicalButton { width: (parent.width-parent.columnSpacing*2)/3; height: (parent.height-parent.rowSpacing)/2; text: "CANCEL"; subtext: "ABORT"; accent: root.red; danger:true; labelScale: .62; onClicked: bridge.requestCommand("cancel") }
                    MechanicalButton { enabled:bridge.eliteControlsReady && !!bridge.navHomeSystem; opacity:enabled?1:.45; width: (parent.width-parent.columnSpacing*2)/3; height: (parent.height-parent.rowSpacing)/2; text: "HOME"; subtext: !bridge.eliteControlsReady?"ELITE BINDS REQUIRED":bridge.navHomeSystem; accent: root.green; labelScale: .64; subtextMinSize: Math.max(12,14*root.scaleUnit); onClicked: { navigationPage.navDraft=bridge.navHomeSystem; navigationPage.navDraftDirty=false; bridge.plotMemory("home") } }
                    MechanicalButton { enabled:bridge.eliteControlsReady && !!bridge.navBookmark1System; opacity:enabled?1:.45; width: (parent.width-parent.columnSpacing*2)/3; height: (parent.height-parent.rowSpacing)/2; text: "BOOKMARK 1"; subtext: !bridge.eliteControlsReady?"ELITE BINDS REQUIRED":(bridge.navBookmark1System || "UNSET"); accent: bridge.navBookmark1System?root.green:root.amber; labelScale: .54; subtextMinSize: Math.max(12,14*root.scaleUnit); onClicked: { if (bridge.navBookmark1System) { navigationPage.navDraft=bridge.navBookmark1System; navigationPage.navDraftDirty=false; bridge.plotMemory("bookmark1") } } }
                    MechanicalButton { enabled:bridge.eliteControlsReady && !!bridge.navBookmark2System; opacity:enabled?1:.45; width: (parent.width-parent.columnSpacing*2)/3; height: (parent.height-parent.rowSpacing)/2; text: "BOOKMARK 2"; subtext: !bridge.eliteControlsReady?"ELITE BINDS REQUIRED":(bridge.navBookmark2System || "UNSET"); accent: bridge.navBookmark2System?root.green:root.amber; labelScale: .54; subtextMinSize: Math.max(12,14*root.scaleUnit); onClicked: { if (bridge.navBookmark2System) { navigationPage.navDraft=bridge.navBookmark2System; navigationPage.navDraftDirty=false; bridge.plotMemory("bookmark2") } } }
                }
                Text {
                    text: "SAVE "+bridge.navMemoryCaptureSource+" // "+bridge.navMemoryCaptureSystem
                    x: 22*root.scaleUnit; y: setMemoryRow.y-Math.max(16,22*root.scaleUnit); width: parent.width-44*root.scaleUnit
                    color: "#8b998f"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(12,16*root.scaleUnit); horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                }
                Row {
                    id: setMemoryRow
                    x: 20*root.scaleUnit
                    y: parent.height-height-10*root.scaleUnit
                    width: parent.width-40*root.scaleUnit; height: Math.max(32,48*root.scaleUnit); spacing: 8*root.scaleUnit
                    MechanicalButton { width: (parent.width-parent.spacing*2)/3; height: parent.height; text: "SET HOME"; accent: root.amber; labelScale: .60; onClicked: bridge.captureNavigationMemory("home") }
                    MechanicalButton { width: (parent.width-parent.spacing*2)/3; height: parent.height; text: "SET BM1"; accent: root.amber; labelScale: .60; onClicked: bridge.captureNavigationMemory("bookmark1") }
                    MechanicalButton { width: (parent.width-parent.spacing*2)/3; height: parent.height; text: "SET BM2"; accent: root.amber; labelScale: .60; onClicked: bridge.captureNavigationMemory("bookmark2") }
                }
            }
        }
    }


    // COMBAT MODULE: command rack, tactical display, RES browser, session and alerts.
    Item {
        id: combatPage
        visible: root.currentPage === 2
        x: identity.x
        y: identity.y + identity.height + root.gap
        width: identity.width
        height: root.height - y - root.m
        property int selectedResIndex: -1
        property int utilityMode: 0  // 0 tactical, 1 RES finder
        property real targetDriftPhase: 0
        property real reticleDriftPhase: 0
        readonly property bool showOrientationDemo: root.firstOrientationActive && root.currentPage === 2
        readonly property bool targetPresent: showOrientationDemo ? true : bridge.combatTargetPresent
        readonly property string targetName: showOrientationDemo ? "ORIENTATION TARGET" : bridge.combatTargetName
        readonly property string targetShip: showOrientationDemo ? "Krait Mk II" : bridge.combatTargetShip
        readonly property string targetFaction: showOrientationDemo ? "DEMO SECURITY CONTACT" : bridge.combatTargetFaction
        readonly property string targetLegal: showOrientationDemo ? "WANTED" : bridge.combatTargetLegal
        readonly property string targetRank: showOrientationDemo ? "DANGEROUS" : bridge.combatTargetRank
        readonly property int targetHullPercent: showOrientationDemo ? 78 : bridge.combatTargetHullPercent
        readonly property int targetShieldPercent: showOrientationDemo ? 46 : bridge.combatTargetShieldPercent
        readonly property string targetBounty: showOrientationDemo ? "842,500 CR" : bridge.combatTargetBounty
        readonly property string targetSubsystem: showOrientationDemo ? "POWER PLANT" : bridge.combatTargetSubsystem
        readonly property int targetSubsystemPercent: showOrientationDemo ? 68 : bridge.combatTargetSubsystemPercent
        readonly property int targetScanStage: showOrientationDemo ? 3 : bridge.combatTargetScanStage
        readonly property bool targetCombatActive: showOrientationDemo ? true : bridge.combatActive
        onUtilityModeChanged: root.publishUiContext()
        NumberAnimation on targetDriftPhase { from: 0; to: 6.28318; duration: 11800; loops: Animation.Infinite; running: combatPage.visible }
        NumberAnimation on reticleDriftPhase { from: 0; to: 6.28318; duration: 7600; loops: Animation.Infinite; running: combatPage.visible }

        Row {
            anchors.fill: parent
            spacing: root.gap

            // Left column: commands always remain visible, including while browsing RES sites.
            MetalPanel {
                id: combatCommandRack
                width: parent.width * .255
                height: parent.height
                panelColor: root.screen
                SectionTitle { text: "COMBAT COMMAND RACK"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }

                Text {
                    x: 22*root.scaleUnit; y: 55*root.scaleUnit; width: parent.width-44*root.scaleUnit
                    text: "DIRECT COCKPIT COMMANDS"
                    color: "#7f8c83"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(11,14*root.scaleUnit)
                }

                Grid {
                    id: combatCommandGrid
                    enabled: bridge.eliteControlsReady
                    opacity: enabled ? 1.0 : .45
                    x: 18*root.scaleUnit; y: 82*root.scaleUnit
                    width: parent.width-36*root.scaleUnit
                    columns: 2; columnSpacing: 8*root.scaleUnit; rowSpacing: 7*root.scaleUnit
                    property real bw: (width-columnSpacing)/2
                    property real bh: Math.max(58,70*root.scaleUnit)

                    MechanicalButton { width: combatCommandGrid.bw; height: combatCommandGrid.bh; text: "HIGHEST THREAT"; subtext: "SELECT TARGET"; accent: root.amber; labelScale: .58; subtextMinSize: Math.max(11,13*root.scaleUnit); onClicked: bridge.requestCommand("combat_threat") }
                    MechanicalButton { width: combatCommandGrid.bw; height: combatCommandGrid.bh; text: "POWER PLANT"; subtext: "WANTED TARGET"; accent: root.amber; labelScale: .62; subtextMinSize: Math.max(11,13*root.scaleUnit); onClicked: bridge.requestCommand("combat_powerplant") }

                    MechanicalButton { width: combatCommandGrid.bw; height: combatCommandGrid.bh; text: "DEPLOY FIGHTER 1"; subtext: "LAUNCH BAY 1"; accent: root.green; labelScale: .55; subtextMinSize: Math.max(11,13*root.scaleUnit); onClicked: bridge.requestCommand("combat_fighter_1") }
                    MechanicalButton { width: combatCommandGrid.bw; height: combatCommandGrid.bh; text: "DEPLOY FIGHTER 2"; subtext: "LAUNCH BAY 2"; accent: root.green; labelScale: .55; subtextMinSize: Math.max(11,13*root.scaleUnit); onClicked: bridge.requestCommand("combat_fighter_2") }

                    MechanicalButton { width: combatCommandGrid.bw; height: combatCommandGrid.bh; text: "RECALL FIGHTER"; subtext: "REQUEST DOCK"; accent: root.amber; labelScale: .58; subtextMinSize: Math.max(11,13*root.scaleUnit); onClicked: bridge.requestCommand("combat_fighter_recall") }
                    MechanicalButton { width: combatCommandGrid.bw; height: combatCommandGrid.bh; text: "FIRE GROUP"; subtext: "CYCLE NEXT"; accent: root.amber; labelScale: .62; subtextMinSize: Math.max(11,13*root.scaleUnit); onClicked: bridge.requestCommand("combat_firegroup_next") }

                    MechanicalButton { width: combatCommandGrid.bw; height: combatCommandGrid.bh; text: "W1 TARGET"; subtext: "TARGET THEIR TARGET"; accent: root.green; labelScale: .62; subtextMinSize: Math.max(10,12*root.scaleUnit); onClicked: bridge.requestCommand("combat_wing_target_1") }
                    MechanicalButton { width: combatCommandGrid.bw; height: combatCommandGrid.bh; text: "NAVLOCK W1"; subtext: "TOGGLE WING LOCK"; accent: root.green; labelScale: .62; subtextMinSize: Math.max(10,12*root.scaleUnit); onClicked: bridge.requestCommand("combat_navlock_1") }

                    MechanicalButton { width: combatCommandGrid.bw; height: combatCommandGrid.bh; text: "W2 TARGET"; subtext: "TARGET THEIR TARGET"; accent: root.green; labelScale: .62; subtextMinSize: Math.max(10,12*root.scaleUnit); onClicked: bridge.requestCommand("combat_wing_target_2") }
                    MechanicalButton { width: combatCommandGrid.bw; height: combatCommandGrid.bh; text: "NAVLOCK W2"; subtext: "TOGGLE WING LOCK"; accent: root.green; labelScale: .62; subtextMinSize: Math.max(10,12*root.scaleUnit); onClicked: bridge.requestCommand("combat_navlock_2") }

                    MechanicalButton { width: combatCommandGrid.bw; height: combatCommandGrid.bh; text: "W3 TARGET"; subtext: "TARGET THEIR TARGET"; accent: root.green; labelScale: .62; subtextMinSize: Math.max(10,12*root.scaleUnit); onClicked: bridge.requestCommand("combat_wing_target_3") }
                    MechanicalButton { width: combatCommandGrid.bw; height: combatCommandGrid.bh; text: "NAVLOCK W3"; subtext: "TOGGLE WING LOCK"; accent: root.green; labelScale: .62; subtextMinSize: Math.max(10,12*root.scaleUnit); onClicked: bridge.requestCommand("combat_navlock_3") }
                }

                MechanicalButton {
                    id: bestTargetButton
                    x: 18*root.scaleUnit; y: combatCommandGrid.y + combatCommandGrid.height + 12*root.scaleUnit
                    width: parent.width-36*root.scaleUnit; height: Math.max(62,74*root.scaleUnit)
                    enabled: bridge.eliteControlsReady
                    opacity: enabled ? 1.0 : .45
                    text: "FIND BEST TARGET"; subtext: enabled?"FULL SWEEP + RANK":"ELITE BINDS REQUIRED"
                    accent: root.amber; labelScale: .78; subtextMinSize: 11
                    onClicked: bridge.requestCommand("combat_best_target")
                }

                MechanicalButton {
                    id: emergencyEscapeButton
                    x: 18*root.scaleUnit; y: bestTargetButton.y + bestTargetButton.height + 8*root.scaleUnit
                    width: parent.width-36*root.scaleUnit; height: Math.max(86,104*root.scaleUnit)
                    enabled: bridge.eliteControlsReady
                    opacity: enabled ? 1.0 : .45
                    text: "ESCAPE AREA"; subtext: enabled?"FULL ENG // BOOST // CHAFF // SUPERCRUISE":"ELITE BINDS REQUIRED"
                    accent: root.red; active: bridge.combatEgressStatus.toUpperCase().indexOf("ACTIVE")>=0
                    labelScale: .92; subtextMinSize: 12
                    onClicked: bridge.requestCommand("combat_egress")
                }

                Text {
                    x: 22*root.scaleUnit; y: emergencyEscapeButton.y + emergencyEscapeButton.height + 12*root.scaleUnit
                    width: parent.width-44*root.scaleUnit
                    text: "AUTOMATION SWITCHES"
                    color: "#7e8e83"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(11,14*root.scaleUnit)
                }
                Column {
                    id: combatAutomationSwitches
                    x: 18*root.scaleUnit; y: emergencyEscapeButton.y + emergencyEscapeButton.height + 36*root.scaleUnit
                    width: parent.width-36*root.scaleUnit; spacing: 8*root.scaleUnit
                    FlipSwitch { width: parent.width; height: Math.max(62,72*root.scaleUnit); scaleUnit: root.scaleUnit; text: "AUTO PIPS"; subtext: checked ? bridge.combatDynamicPipsMode : "PILOT CONTROL"; checked: bridge.combatDynamicPipsEnabled; accent: root.green; onToggled: bridge.requestCommand("combat_toggle_pips") }
                    FlipSwitch { width: parent.width; height: Math.max(62,72*root.scaleUnit); scaleUnit: root.scaleUnit; text: "AUTO SUBSYSTEM"; subtext: checked ? "POWER PLANT TARGETING" : "MANUAL TARGETING"; checked: bridge.combatAutoSubsystemEnabled; accent: root.green; onToggled: bridge.requestCommand("combat_toggle_subsystem") }
                }

                Rectangle {
                    id: combatCommandFeedback
                    x: 18*root.scaleUnit; y: parent.height-height-14*root.scaleUnit
                    width: parent.width-36*root.scaleUnit; height: Math.max(92,112*root.scaleUnit)
                    color: "#0b1710"
                    property string commandText: String(bridge.combatCommandStatus || "-")
                    property string transientCommandText: "-"
                    property string egressText: String(bridge.combatEgressStatus || "-")
                    onCommandTextChanged: {
                        if (commandText !== "-") { transientCommandText = commandText; commandStatusClear.restart() }
                    }
                    Timer { id: commandStatusClear; interval: 10000; repeat: false; onTriggered: combatCommandFeedback.transientCommandText = "-" }
                    property bool egressUrgent: egressText.toUpperCase().indexOf("ACTIVE")>=0 || egressText.toUpperCase().indexOf("FAILED")>=0 || egressText.toUpperCase().indexOf("REFUSED")>=0
                    property string displayText: (egressUrgent ? egressText : (transientCommandText !== "-" ? transientCommandText : "READY // SELECT A COMBAT COMMAND")).toUpperCase()
                    property bool badState: displayText.indexOf("FAILED")>=0 || displayText.indexOf("REFUSED")>=0 || displayText.indexOf("BLOCKED")>=0 || displayText.indexOf("UNAVAILABLE")>=0
                    property bool warnState: !badState && (displayText.indexOf("NO ")>=0 || displayText.indexOf("UNCONFIRMED")>=0 || displayText.indexOf("CHECK ")>=0 || bridge.controlOwner !== "NONE")
                    border.color: egressUrgent ? root.red : (badState ? root.red : (warnState ? root.amber : "#41614a")); border.width: 1

                    Text {
                        x: 10*root.scaleUnit; y: 8*root.scaleUnit; width: parent.width-20*root.scaleUnit; height: 18*root.scaleUnit
                        text: "COMMAND STATUS"
                        color: "#f2f4ef"
                        font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(13,16*root.scaleUnit)
                    }
                    Rectangle { x: 10*root.scaleUnit; y: 29*root.scaleUnit; width: parent.width-20*root.scaleUnit; height: 1; color: "#31533b"; opacity: .8 }
                    Text {
                        text: combatCommandFeedback.displayText
                        x: 10*root.scaleUnit; y: 37*root.scaleUnit; width: parent.width-20*root.scaleUnit; height: parent.height-45*root.scaleUnit
                        color: "#ffffff"
                        font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(13,16*root.scaleUnit)
                        wrapMode: Text.WordWrap; maximumLineCount: 4; elide: Text.ElideRight; verticalAlignment: Text.AlignTop
                    }
                }
            }

            // Center column: two explicit modes only. Nothing needs to be minimized.
            MetalPanel {
                id: combatCenter
                width: parent.width * .455
                height: parent.height
                panelColor: root.screen

                Rectangle {
                    id: combatModeBank
                    x: 0; y: 0; width: parent.width; height: 112*root.scaleUnit
                    color: "#070907"; border.color: "#4d493c"; border.width: 1
                    Text { text: "COMBAT MODE SELECT"; x: 18*root.scaleUnit; y: 8*root.scaleUnit; color: root.amber; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,12*root.scaleUnit) }
                    Text { text: "ONE MODE ACTIVE AT A TIME"; anchors.right: parent.right; anchors.rightMargin: 18*root.scaleUnit; y: 8*root.scaleUnit; color: root.muted; font.family: "Consolas"; font.pixelSize: Math.max(10,10*root.scaleUnit) }
                    Row {
                        id: combatWorkspaceTabs
                        x: 18*root.scaleUnit; y: 30*root.scaleUnit; width: parent.width-36*root.scaleUnit; height: 72*root.scaleUnit; spacing: 10*root.scaleUnit
                        Repeater {
                            model: [
                                {label:"TACTICAL VIEW", detail:"TARGET + SUPPORT"},
                                {label:"RES FINDER VIEW", detail:"RESOURCE SITE BROWSER"}
                            ]
                            TradeModeButton {
                                required property int index
                                required property var modelData
                                width: (combatWorkspaceTabs.width-combatWorkspaceTabs.spacing)/2; height: parent.height
                                text: modelData.label
                                subtext: modelData.detail
                                active: combatPage.utilityMode===index
                                accent: root.green
                                scaleUnit: root.scaleUnit
                                onClicked: combatPage.utilityMode=index
                            }
                        }
                    }
                }

                Item {
                    id: tacticalMode
                    visible: combatPage.utilityMode===0
                    x: 20*root.scaleUnit; y: 124*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: parent.height-144*root.scaleUnit

                    Rectangle {
                        x: 0; y: 0; width: parent.width; height: 64*root.scaleUnit
                        color: "#07110a"; border.color: bridge.combatUnderAttack ? root.red : (bridge.combatThreatWarning !== "-" ? root.red : (bridge.combatScanAlertActive ? root.amber : (combatPage.targetCombatActive ? root.amber : root.green))); border.width: 1
                        Text {
                            text: bridge.combatUnderAttack ? "UNDER ATTACK" : (bridge.combatThreatWarning !== "-" ? "POSSIBLE ATTACK // HOSTILE CHAT" : (bridge.combatScanAlertActive ? "SHIP SCAN DETECTED" : (combatPage.targetCombatActive ? "COMBAT ACTIVE" : "COMBAT IDLE")))
                            anchors.centerIn: parent
                            color: bridge.combatUnderAttack ? root.red : (bridge.combatThreatWarning !== "-" ? root.red : (bridge.combatScanAlertActive ? root.amber : (combatPage.targetCombatActive ? root.amber : root.green)))
                            font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(20,34*root.scaleUnit)
                        }
                    }

                    Rectangle {
                        id: targetScopeNew
                        x: 0; y: 78*root.scaleUnit; width: parent.width; height: parent.height * .50
                        color: "#061008"; border.color: combatPage.targetPresent ? root.green : "#405045"; border.width: 1
                        clip: true

                        Text {
                            text: "TARGET // "+combatPage.targetName
                            x: 14*root.scaleUnit; y: 9*root.scaleUnit; width: parent.width-28*root.scaleUnit
                            color: combatPage.targetPresent ? root.green : "#718178"
                            font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(16,22*root.scaleUnit); elide: Text.ElideRight
                        }
                        Text {
                            text: combatPage.targetPresent
                                  ? (String(combatPage.targetShip).replace(/_/g," ").toUpperCase()+"  //  "+String(combatPage.targetFaction).toUpperCase()+"  //  SCAN "+combatPage.targetScanStage+"/3")
                                  : "WAITING FOR SHIP TARGET"
                            x: 14*root.scaleUnit; y: 38*root.scaleUnit; width: parent.width-28*root.scaleUnit
                            color: "#7f9988"; font.family: "Consolas"; font.pixelSize: Math.max(11,14*root.scaleUnit); elide: Text.ElideRight
                        }

                        Item {
                            id: targetTelemetryBody
                            x: 12*root.scaleUnit; y: 66*root.scaleUnit
                            width: parent.width-24*root.scaleUnit; height: parent.height-78*root.scaleUnit

                            Rectangle {
                                id: targetLeftIntel
                                x: 0; y: 0; width: parent.width*.275; height: parent.height
                                color: "#040a06"; border.color: "#234b30"; border.width: 1
                                Column {
                                    x: 14*root.scaleUnit; y: 10*root.scaleUnit; width: parent.width-28*root.scaleUnit; spacing: 7*root.scaleUnit
                                    Repeater {
                                        model: [
                                            ["HULL", combatPage.targetHullPercent>=0 ? combatPage.targetHullPercent+"%" : "-", combatPage.targetHullPercent>=0 && combatPage.targetHullPercent<40 ? root.red : root.green],
                                            ["SHIELDS", combatPage.targetShieldPercent>=0 ? combatPage.targetShieldPercent+"%" : "-", combatPage.targetShieldPercent===0 ? root.red : root.green],
                                            ["LEGAL", combatPage.targetLegal, String(combatPage.targetLegal).toUpperCase()==="WANTED" ? root.red : root.green],
                                            ["RANK", combatPage.targetRank, root.amber]
                                        ]
                                        Item {
                                            width: parent.width; height: Math.max(38,46*root.scaleUnit)
                                            Text {
                                                text: modelData[0]
                                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                                color: "#839487"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(11,14*root.scaleUnit)
                                            }
                                            Text {
                                                text: String(modelData[1]).toUpperCase()
                                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width*.66; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
                                                color: modelData[2]; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(14,19*root.scaleUnit)
                                                fontSizeMode: Text.HorizontalFit; minimumPixelSize: Math.max(11,13*root.scaleUnit)
                                            }
                                        }
                                    }
                                }
                                Text {
                                    visible: combatPage.targetPresent && combatPage.targetSubsystem !== "-"
                                    text: "SUBSYSTEM // "+String(combatPage.targetSubsystem).toUpperCase()+(combatPage.targetSubsystemPercent>=0 ? "  "+combatPage.targetSubsystemPercent+"%" : "")
                                    x: 14*root.scaleUnit; y: parent.height-31*root.scaleUnit; width: parent.width-28*root.scaleUnit
                                    color: "#70867a"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,11*root.scaleUnit); elide: Text.ElideRight
                                }
                            }

                            Item {
                                id: targetVisualStack
                                x: targetLeftIntel.width + 10*root.scaleUnit; y: 0
                                width: parent.width - x; height: parent.height

                                Rectangle {
                                    id: targetVisualWell
                                    x: 0; y: 0; width: parent.width; height: parent.height - Math.max(56,68*root.scaleUnit)
                                    color: "#020805"; border.color: combatPage.targetPresent ? "#256c3d" : "#283b30"; border.width: 1
                                    clip: true
                                    ScanGrid { anchors.fill: parent; opacity: .12; step: Math.max(18,24*root.scaleUnit); majorEvery: 5 }
                                    Image {
                                        id: combatTargetArt
                                        anchors.fill: parent; anchors.margins: 1*root.scaleUnit
                                        source: combatPage.targetPresent && combatPage.targetShip !== "-" ? root.shipArtSource(combatPage.targetShip) : "assets/ship_unknown.png"
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true; mipmap: true
                                        opacity: combatPage.targetPresent ? .68 : .15
                                        scale: combatPage.targetPresent ? 1.34 : 1.0
                                        transform: Translate {
                                            x: combatPage.targetPresent ? (14*root.scaleUnit + Math.sin(combatPage.targetDriftPhase) * 9*root.scaleUnit) : 0
                                            y: combatPage.targetPresent ? Math.cos(combatPage.targetDriftPhase*0.83) * 6*root.scaleUnit : 0
                                        }
                                    }
                                    Reticle {
                                        width: Math.min(parent.width,parent.height)*.72; height: width
                                        x: (parent.width-width)/2 + 14*root.scaleUnit + (combatPage.targetPresent ? Math.sin(combatPage.reticleDriftPhase+0.65)*18*root.scaleUnit : 0)
                                        y: (parent.height-height)/2 + (combatPage.targetPresent ? Math.cos(combatPage.reticleDriftPhase*0.92+0.2)*11*root.scaleUnit : 0)
                                        color: combatPage.targetPresent ? root.green : "#3d5145"; phase: bridge.pulse; opacity: combatPage.targetPresent ? 1.0 : .38
                                    }
                                    Rectangle {
                                        visible: combatPage.targetPresent && combatPage.targetScanStage>=3
                                        anchors.fill: parent; anchors.margins: 5*root.scaleUnit
                                        color: "transparent"; border.color: root.green; border.width: 1
                                        opacity: .18 + .10*Math.sin(bridge.pulse*6.28318)
                                    }
                                }

                                Rectangle {
                                    id: targetBountyBar
                                    x: 0; y: targetVisualWell.height + 8*root.scaleUnit; width: parent.width; height: parent.height-y
                                    color: "#071009"; border.color: String(combatPage.targetLegal).toUpperCase()==="WANTED" ? root.red : root.amber; border.width: 2
                                    Text {
                                        text: combatPage.targetPresent ? ("BOUNTY // "+combatPage.targetBounty) : "BOUNTY // -"
                                        anchors.centerIn: parent; width: parent.width-22*root.scaleUnit
                                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                        color: String(combatPage.targetLegal).toUpperCase()==="WANTED" ? root.red : root.amber
                                        font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(20,30*root.scaleUnit)
                                        fontSizeMode: Text.HorizontalFit; minimumPixelSize: Math.max(16,20*root.scaleUnit); elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        text: bridge.combatTacticalAdvisory
                        x: 0; y: targetScopeNew.y + targetScopeNew.height + 8*root.scaleUnit
                        width: parent.width; height: 24*root.scaleUnit
                        color: "#91a197"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,12*root.scaleUnit); elide: Text.ElideRight
                    }
                    Grid {
                        x: 0; y: targetScopeNew.y + targetScopeNew.height + 36*root.scaleUnit
                        width: parent.width; height: parent.height-y
                        columns: 2; columnSpacing: 10*root.scaleUnit; rowSpacing: 6*root.scaleUnit
                        Repeater {
                            model: bridge.combatSupportRows
                            StatusLamp { width: (parent.width-parent.columnSpacing)/2; height: Math.max(36,42*root.scaleUnit); label: modelData.label; value: modelData.value; stateColor: bridge.levelColor(modelData.level); pulse: index===0 && bridge.combatCollectorUpperBound>0; phase: bridge.pulse; fontScale: 1.18 }
                        }
                    }
                }

                Item {
                    id: resMode
                    visible: combatPage.utilityMode===1
                    x: 20*root.scaleUnit; y: 124*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: parent.height-144*root.scaleUnit

                    Row {
                        x: 0; y: 0; width: parent.width; height: 64*root.scaleUnit; spacing: 9*root.scaleUnit
                        MechanicalButton { width: 180*root.scaleUnit; height: parent.height; text: "HIGH RES"; subtext: "SEARCH"; accent: root.green; labelScale: .82; subtextMinSize: 13; onClicked: { combatPage.selectedResIndex=-1; bridge.requestCommand("combat_res_high") } }
                        MechanicalButton { width: 180*root.scaleUnit; height: parent.height; text: "HAZ RES"; subtext: "SEARCH"; accent: root.red; labelScale: .82; subtextMinSize: 13; onClicked: { combatPage.selectedResIndex=-1; bridge.requestCommand("combat_res_haz") } }
                        Column {
                            width: parent.width-378*root.scaleUnit; height: parent.height; spacing: 4*root.scaleUnit
                            Text { text: bridge.combatResBusy ? "SEARCHING..." : bridge.combatResStatus.toUpperCase(); color: bridge.combatResBusy ? root.amber : "#a9b4ac"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(11,14*root.scaleUnit); width: parent.width; elide: Text.ElideRight }
                            Text { text: "MAX 50 // FILTER <= 10,000 LS"; color: "#6d7a71"; font.family: "Consolas"; font.pixelSize: Math.max(10,12*root.scaleUnit); width: parent.width; elide: Text.ElideRight }
                        }
                    }

                    Rectangle {
                        id: resTallTable
                        x: 0; y: 76*root.scaleUnit; width: parent.width; height: parent.height-154*root.scaleUnit
                        color: "#050d07"; border.color: "#2e4434"; border.width: 1
                        Rectangle {
                            x: 1; y: 1; width: parent.width-2; height: 36*root.scaleUnit; color: "#0a140c"; border.color: "#24362a"; border.width: 1
                            Text { text: "TYPE"; x: 14*root.scaleUnit; width: parent.width*.17; anchors.verticalCenter: parent.verticalCenter; color: "#b4beb7"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(11,13*root.scaleUnit) }
                            Text { text: "SYSTEM"; x: parent.width*.19; width: parent.width*.33; anchors.verticalCenter: parent.verticalCenter; color: "#b4beb7"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(11,13*root.scaleUnit) }
                            Text { text: "BODY"; x: parent.width*.53; width: parent.width*.17; anchors.verticalCenter: parent.verticalCenter; color: "#b4beb7"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(11,13*root.scaleUnit) }
                            Text { text: "LY"; x: parent.width*.72; width: parent.width*.09; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight; color: "#b4beb7"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(11,13*root.scaleUnit) }
                            Text { text: "LS"; anchors.right: parent.right; anchors.rightMargin: 24*root.scaleUnit; width: parent.width*.14; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight; color: "#b4beb7"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(11,13*root.scaleUnit) }
                        }
                        ListView {
                            id: resResultListTall
                            x: 4*root.scaleUnit; y: 41*root.scaleUnit; width: parent.width-16*root.scaleUnit; height: parent.height-46*root.scaleUnit
                            clip: true; spacing: 2*root.scaleUnit; model: bridge.combatResRows; boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn; width: Math.max(12,14*root.scaleUnit) }
                            delegate: Rectangle {
                                width: resResultListTall.width; height: Math.max(34,38*root.scaleUnit); radius: 2
                                color: combatPage.selectedResIndex===index ? "#0d2617" : (index%2===0 ? "#071009" : "#09120b")
                                border.color: combatPage.selectedResIndex===index ? root.green : "#263c2d"; border.width: combatPage.selectedResIndex===index ? 2 : 1
                                Rectangle { width: 6*root.scaleUnit; height: parent.height-8*root.scaleUnit; x: 3*root.scaleUnit; y: 4*root.scaleUnit; color: String(modelData.type).toUpperCase().indexOf("HAZ")>=0 ? root.red : root.green }
                                Text { text: String(modelData.type).toUpperCase(); x: 14*root.scaleUnit; width: parent.width*.17; anchors.verticalCenter: parent.verticalCenter; color: String(modelData.type).toUpperCase().indexOf("HAZ")>=0 ? root.red : root.green; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,12*root.scaleUnit); elide: Text.ElideRight }
                                Text { text: String(modelData.system).toUpperCase(); x: parent.width*.19; width: parent.width*.33; anchors.verticalCenter: parent.verticalCenter; color: root.whiteText; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,12*root.scaleUnit); elide: Text.ElideRight }
                                Text { text: String(modelData.body).toUpperCase(); x: parent.width*.53; width: parent.width*.17; anchors.verticalCenter: parent.verticalCenter; color: "#a5b1a8"; font.family: "Consolas"; font.pixelSize: Math.max(10,12*root.scaleUnit); elide: Text.ElideRight }
                                Text { text: String(modelData.distanceLy); x: parent.width*.72; width: parent.width*.09; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight; color: root.amber; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,12*root.scaleUnit) }
                                Text { text: String(modelData.distanceLs); anchors.right: parent.right; anchors.rightMargin: 18*root.scaleUnit; width: parent.width*.14; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight; color: Number(modelData.resLs)>=8000 ? root.amber : root.green; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,12*root.scaleUnit) }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: combatPage.selectedResIndex=index }
                            }
                        }
                        Text { visible: bridge.combatResRows.length===0; anchors.centerIn: parent; text: bridge.combatResBusy ? "SEARCH IN PROGRESS" : "RUN A HIGH OR HAZ RES SEARCH"; color: "#738078"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(12,15*root.scaleUnit) }
                    }

                    Row {
                        x: 0; y: parent.height-height; width: parent.width; height: 66*root.scaleUnit; spacing: 9*root.scaleUnit
                        Item { width:(parent.width-parent.spacing)/2; height:parent.height
                            MechanicalButton { anchors.fill:parent; text:"PLOT SELECTED"; subtext:combatPage.selectedResIndex>=0?"ROUTE TO SELECTED SITE":"SELECT A ROW"; accent:combatPage.selectedResIndex>=0?root.green:"#59625a"; labelScale:.74; subtextMinSize:12; onClicked:{ if(combatPage.selectedResIndex>=0){bridge.plotResIndex(combatPage.selectedResIndex);combatPage.selectedResIndex=-1} } }
                            Rectangle { anchors.fill:parent; anchors.margins:-4*root.scaleUnit; visible:combatPage.selectedResIndex>=0; color:"transparent"; border.color:root.amber; border.width:Math.max(2,3*root.scaleUnit); SequentialAnimation on opacity{running:parent.visible;loops:Animation.Infinite;NumberAnimation{to:.28;duration:420}
                                NumberAnimation{to:1;duration:420}} }
                        }
                        MechanicalButton { width: (parent.width-parent.spacing)/2; height: parent.height; text: "PLOT NEAREST"; subtext: bridge.combatResRows.length>0 ? "FIRST RESULT" : "NO RESULT"; accent: bridge.combatResRows.length>0 ? root.green : "#59625a"; labelScale: .74; subtextMinSize: 12; onClicked: { if (bridge.combatResRows.length>0) bridge.requestCommand("combat_res_plot") } }
                    }
                }
            }

            // Right column: persistent context. These never disappear when RES Finder is open.
            Column {
                id: combatRight
                width: parent.width - combatCommandRack.width - combatCenter.width - root.gap*2
                height: parent.height
                spacing: root.gap

                MetalPanel {
                    width: parent.width; height: parent.height*.25
                    panelColor: root.screen
                    SectionTitle { text: "COMBAT SESSION"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }
                    Column {
                        x: 22*root.scaleUnit; y: 60*root.scaleUnit; width: parent.width-44*root.scaleUnit; spacing: 4*root.scaleUnit
                        Repeater { model: bridge.combatSessionRows
                            Item { width: parent.width; height: 28*root.scaleUnit
                                Rectangle { width: 7*root.scaleUnit; height: width; radius: width/2; color: bridge.levelColor(modelData.level); anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: modelData.label; x: 17*root.scaleUnit; color: "#94a096"; font.family: "Consolas"; font.pixelSize: Math.max(11,14*root.scaleUnit); anchors.verticalCenter: parent.verticalCenter }
                                Text { text: modelData.value; anchors.right: parent.right; width: parent.width*.55; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight; color: bridge.levelColor(modelData.level); font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(11,14*root.scaleUnit); anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                    }
                }

                MetalPanel {
                    width: parent.width; height: parent.height*.31
                    panelColor: root.screen
                    SectionTitle { text: "COMBAT ALERTS"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }
                    Column {
                        x: 22*root.scaleUnit; y: 60*root.scaleUnit; width: parent.width-44*root.scaleUnit; spacing: 4*root.scaleUnit
                        Repeater { model: bridge.combatAlertRows
                            Item { width: parent.width; height: 40*root.scaleUnit
                                Rectangle { width: 9*root.scaleUnit; height: width; radius: width/2; color: bridge.levelColor(modelData.level); anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; opacity: .72 + .20*Math.sin((bridge.pulse+index*.13)*6.28318) }
                                Text { text: modelData.label; x: 19*root.scaleUnit; width: parent.width*.40; color: root.whiteText; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(11,14*root.scaleUnit); anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight }
                                Text { text: modelData.value; anchors.right: parent.right; width: parent.width*.55; horizontalAlignment: Text.AlignRight; wrapMode: Text.WordWrap; maximumLineCount: 2; color: bridge.levelColor(modelData.level); font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,13*root.scaleUnit); anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                    }
                }

                MetalPanel {
                    width: parent.width; height: parent.height - parent.children[0].height - parent.children[1].height - root.gap*2
                    panelColor: root.screen
                    SectionTitle { text: "COMBAT STATUS"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }
                    Grid {
                        x: 18*root.scaleUnit; y: 58*root.scaleUnit; width: parent.width-36*root.scaleUnit
                        columns: 2; columnSpacing: 8*root.scaleUnit; rowSpacing: 4*root.scaleUnit
                        Repeater { model: bridge.combatStatusRows
                            StatusLamp { width: (parent.width-parent.columnSpacing)/2; height: Math.max(30,34*root.scaleUnit); label: modelData.label; value: modelData.value; stateColor: bridge.levelColor(modelData.level); pulse: modelData.label === "UNDER ATTACK" && modelData.value === "YES"; phase: bridge.pulse; fontScale: 1.02 }
                        }
                    }
                }
            }
        }
    }


    // TRADE MODULE: best-trade discovery + commodity route finder + trade-loop control.
    Item {
        id: tradePage
        visible: root.currentPage === 3
        x: identity.x
        y: identity.y + identity.height + root.gap
        width: identity.width
        height: root.height - y - root.m

        property int tradeView: 2 // 0 trade loop, 1 route finder, 2 best trade; Best Trade is the default workspace
        onTradeViewChanged: root.publishUiContext()
        property string selectedCommodityValue: (bridge.tradeCommodity && bridge.tradeCommodity !== "-") ? bridge.tradeCommodity : ""
        property string commodityQuery: ""
        property int selectedRouteIndex: -1
        property int selectedBestRouteIndex: -1
        property int legalityIndex: 0
        property int rareModeIndex: 0
        property var legalityValues: ["LEGAL ONLY","ALLOW RESTRICTED"]
        property var rareModeValues: ["EXCLUDE","ALLOW"]
        property int maxLyIndex: 2
        property int maxStartLyIndex: 2
        property int maxLsIndex: 2 // 5,000 LS default for Route Finder + Best Trade
        property int minRunsIndex: 2 // 10-run sustainability default for Route Finder + Best Trade
        property int runLengthIndex: 0
        property var maxLyValues: [25,50,100,200]
        property var maxStartLyValues: [25,50,100,200]
        property var maxLsValues: [1000,2500,5000,10000]
        property var minRunsValues: [1,5,10,25]
        property var runLengthValues: ["CONTINUOUS","5 CYCLES","10 CYCLES","25 CYCLES","50 CYCLES","100 CYCLES"]

        function filteredCommodities() {
            var out=[]; var q=String(commodityQuery||"").toLowerCase(); var m=bridge.tradeCommodityOptions || []
            for (var i=0;i<m.length;i++) if (!q || String(m[i]).toLowerCase().indexOf(q)>=0) out.push(m[i])
            return out
        }
        function runLengthValue() { return runLengthValues[runLengthIndex] }
        function saveProfile() {
            bridge.saveTradeProfile(selectedCommodityValue, String(bridge.tradePlannedCargo), bridge.tradeBuySystem, bridge.tradeBuyStation,
                                    bridge.tradeSellSystem, bridge.tradeSellStation, runLengthValue())
        }
        function startRun() {
            bridge.startTradeRun(selectedCommodityValue, String(bridge.tradePlannedCargo), bridge.tradeBuySystem, bridge.tradeBuyStation,
                                 bridge.tradeSellSystem, bridge.tradeSellStation, runLengthValue())
        }
        function searchRoutes() {
            selectedRouteIndex=-1
            bridge.searchTradeRoutes(selectedCommodityValue, String(maxLyValues[maxLyIndex]), String(maxLsValues[maxLsIndex]), String(minRunsValues[minRunsIndex]))
        }
        function searchBestTrade() {
            selectedBestRouteIndex=-1
            bridge.searchBestTrade(String(maxStartLyValues[maxStartLyIndex]), String(maxLyValues[maxLyIndex]), String(maxLsValues[maxLsIndex]), String(minRunsValues[minRunsIndex]), legalityValues[legalityIndex], rareModeValues[rareModeIndex])
        }
        function tradeViewForTab(tabIndex) { return tabIndex===0 ? 2 : (tabIndex===1 ? 1 : 0) }

        // Three physically-latching trade-mode selectors. The active mode sits
        // recessed with its own illuminated annunciator, while hover stays visually
        // distinct from selection so the pilot always knows which workspace is live.
        Rectangle {
            id: tradeTabs
            x: 0; y: 0; width: parent.width; height: 112*root.scaleUnit
            color: "#070907"; border.color: "#4d493c"; border.width: 1
            Text { text: "TRADE MODE SELECT"; x: 18*root.scaleUnit; y: 8*root.scaleUnit; color: root.amber; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,12*root.scaleUnit) }
            Text { text: "ONE MODE ACTIVE AT A TIME"; anchors.right: parent.right; anchors.rightMargin: 18*root.scaleUnit; y: 8*root.scaleUnit; color: root.muted; font.family: "Consolas"; font.pixelSize: Math.max(10,10*root.scaleUnit) }
            Row {
                x: 18*root.scaleUnit; y: 30*root.scaleUnit; width: parent.width-36*root.scaleUnit; height: 72*root.scaleUnit; spacing: 10*root.scaleUnit
                Repeater {
                    model: [
                        {label:"BEST TRADE", detail:"MARKET SCAN"},
                        {label:"ROUTE FINDER", detail:"COMMODITY ROUTES"},
                        {label:"TRADE LOOP", detail:"MANAGE ACTIVE LOOP"}
                    ]
                    TradeModeButton {
                        required property int index
                        required property var modelData
                        width: parent.width/3-parent.spacing*2/3; height: parent.height
                        text: modelData.label
                        subtext: modelData.detail
                        active: tradePage.tradeView===tradePage.tradeViewForTab(index)
                        accent: root.green
                        scaleUnit: root.scaleUnit
                        onClicked: tradePage.tradeView=tradePage.tradeViewForTab(index)
                    }
                }
            }
        }

        // THEMED COMMODITY PICKER. Search text filters a fixed list; arbitrary text can never be committed.
        Popup {
            id: commodityPopup
            modal: true; focus: true
            x: Math.max(20*root.scaleUnit, (tradePage.width-width)/2)
            y: 80*root.scaleUnit
            width: Math.min(720*root.scaleUnit, tradePage.width-40*root.scaleUnit)
            height: Math.min(760*root.scaleUnit, tradePage.height-100*root.scaleUnit)
            padding: 0
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
            onClosed: {
                tradePage.commodityQuery = ""
                commoditySearch.text = ""
                commoditySearch.focus = false
                tradePage.forceActiveFocus()
            }
            background: Rectangle { color: "#070b08"; border.color: root.green; border.width: 2 }
            contentItem: Item {
                Text { text: "SELECT TRADE COMMODITY"; x: 20*root.scaleUnit; y: 16*root.scaleUnit; color: root.green; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(16,21*root.scaleUnit) }
                TextField {
                    id: commoditySearch; x: 20*root.scaleUnit; y: 52*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 45*root.scaleUnit
                    placeholderText: "SEARCH COMMODITIES..."; text: tradePage.commodityQuery
                    onTextChanged: tradePage.commodityQuery=text
                    color: root.whiteText; placeholderTextColor: root.muted; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(13,16*root.scaleUnit)
                    background: Rectangle { color: "#08110b"; border.color: commoditySearch.activeFocus ? root.green : "#35513f"; border.width: 1 }
                }
                ListView {
                    id: commodityList; x: 20*root.scaleUnit; y: 108*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: parent.height-128*root.scaleUnit
                    clip: true; model: tradePage.filteredCommodities(); spacing: 2*root.scaleUnit
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn }
                    delegate: Rectangle {
                        required property string modelData; required property int index
                        width: commodityList.width-(commodityList.ScrollBar.vertical.visible?14*root.scaleUnit:0); height: 40*root.scaleUnit
                        color: modelData===tradePage.selectedCommodityValue ? "#103821" : (index%2===0 ? "#08100b" : "#060a07")
                        border.color: modelData===tradePage.selectedCommodityValue ? root.green : "#1d3828"; border.width: 1
                        Text { anchors.left: parent.left; anchors.leftMargin: 12*root.scaleUnit; anchors.verticalCenter: parent.verticalCenter; text: modelData; color: modelData===tradePage.selectedCommodityValue?root.green:root.whiteText; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(12,15*root.scaleUnit) }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                // Close first. Clearing the filter rebuilds this delegate, so doing that
                                // before close() can interrupt the click handler after the first use.
                                tradePage.selectedCommodityValue = modelData
                                commodityPopup.close()
                            }
                        }
                    }
                }
            }
        }


        Popup {
            id: runLengthPopup
            modal: true
            focus: true
            width: 280*root.scaleUnit
            height: Math.min(330*root.scaleUnit, tradePage.height-120*root.scaleUnit)
            x: Math.max(20*root.scaleUnit, tradePage.width*.46-width/2)
            y: 120*root.scaleUnit
            padding: 0
            background: Rectangle { color:"#070b08"; border.color:root.green; border.width:2 }
            contentItem: Item {
                Text {
                    text:"SELECT RUN LENGTH"
                    x:18*root.scaleUnit; y:14*root.scaleUnit
                    color:root.green; font.family:"Consolas"; font.bold:true
                    font.pixelSize:Math.max(14,18*root.scaleUnit)
                }
                ListView {
                    id: runLengthList
                    x:16*root.scaleUnit; y:48*root.scaleUnit
                    width:parent.width-32*root.scaleUnit
                    height:parent.height-64*root.scaleUnit
                    clip:true
                    model:tradePage.runLengthValues
                    spacing:3*root.scaleUnit
                    delegate: Rectangle {
                        required property string modelData
                        required property int index
                        width:runLengthList.width
                        height:42*root.scaleUnit
                        color:index===tradePage.runLengthIndex ? "#103821" : "#08100b"
                        border.color:index===tradePage.runLengthIndex ? root.green : "#284332"
                        border.width:index===tradePage.runLengthIndex ? 2 : 1
                        Text {
                            anchors.centerIn:parent
                            text:modelData
                            color:index===tradePage.runLengthIndex ? root.green : root.whiteText
                            font.family:"Consolas"; font.bold:true
                            font.pixelSize:Math.max(12,15*root.scaleUnit)
                        }
                        MouseArea {
                            anchors.fill:parent
                            onClicked:{
                                tradePage.runLengthIndex=index
                                Qt.callLater(function(){
                                    runLengthPopup.close()
                                    runLengthPopup.visible=false
                                })
                            }
                        }
                    }
                }
            }
        }

        // TRADE LOOP WORKSPACE
        // TRADE WORKSPACE // TRADE LOOP
        Item {
            visible: tradePage.tradeView===0
            x: 0; y: tradeTabs.height + root.gap; width: parent.width; height: parent.height-y

            Row {
                id: tradeSetupTop
                width: parent.width
                // The left profile has fixed-height controls down through the loop-status strip.
                // Reserve enough room at 2560x1440 while still leaving a useful live ledger below.
                height: Math.min(parent.height-root.gap-250*root.scaleUnit, Math.max(parent.height*.56, 575*root.scaleUnit))
                spacing: root.gap
                MetalPanel {
                    width: parent.width*.46; height: parent.height; panelColor: root.screen
                    SectionTitle { text: "TRADE LOOP PROFILE"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }

                    Text { text: "COMMODITY"; x: 24*root.scaleUnit; y: 62*root.scaleUnit; color: root.muted; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(11,13*root.scaleUnit) }
                    Rectangle {
                        x: 24*root.scaleUnit; y: 82*root.scaleUnit; width: parent.width*.52; height: 52*root.scaleUnit
                        color: "#07110a"; border.color: root.green; border.width: 1
                        Text { anchors.left: parent.left; anchors.leftMargin: 14*root.scaleUnit; anchors.verticalCenter: parent.verticalCenter; width: parent.width-64*root.scaleUnit; text: tradePage.selectedCommodityValue.toUpperCase(); color: root.green; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(14,19*root.scaleUnit); elide: Text.ElideRight }
                        Text { anchors.right: parent.right; anchors.rightMargin: 14*root.scaleUnit; anchors.verticalCenter: parent.verticalCenter; text: "▼"; color: root.green; font.pixelSize: Math.max(14,18*root.scaleUnit) }
                        MouseArea { anchors.fill: parent; onClicked: { tradePage.commodityQuery=""; commodityPopup.open(); commoditySearch.forceActiveFocus() } }
                    }
                    Rectangle {
                        x: parent.width*.56; y: 82*root.scaleUnit; width: parent.width*.18; height: 52*root.scaleUnit; color: "#07110a"; border.color: "#5a4930"; border.width: 1
                        Text { text: "SHIP CARGO"; x: 8*root.scaleUnit; y: 5*root.scaleUnit; color: root.muted; font.family: "Consolas"; font.pixelSize: Math.max(10,11*root.scaleUnit) }
                        Text { anchors.centerIn: parent; anchors.verticalCenterOffset: 8*root.scaleUnit; text: bridge.cargoCapacity>=0 ? root.fmtNumber(bridge.cargoCapacity)+" T" : "?"; color: root.amber; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(14,18*root.scaleUnit) }
                    }
                    Rectangle {
                        x: parent.width*.76; y: 82*root.scaleUnit; width: parent.width*.20-24*root.scaleUnit; height: 52*root.scaleUnit
                        color: "#07110a"; border.color: root.green; border.width: 2
                        Text { text: "RUN LENGTH"; x: 8*root.scaleUnit; y: 5*root.scaleUnit; color: root.muted; font.family: "Consolas"; font.pixelSize: Math.max(10,11*root.scaleUnit) }
                        Text { x:8*root.scaleUnit; y:24*root.scaleUnit; width:parent.width-38*root.scaleUnit; text:tradePage.runLengthValue(); color:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit); elide:Text.ElideRight }
                        Text { anchors.right:parent.right; anchors.rightMargin:10*root.scaleUnit; y:23*root.scaleUnit; text:"▼"; color:root.green; font.bold:true; font.pixelSize:Math.max(12,16*root.scaleUnit) }
                        MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked:{ runLengthPopup.open() } }
                    }

                    Text { text: "ACTIVE ROUTE"; x: 24*root.scaleUnit; y: 151*root.scaleUnit; color: root.muted; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(11,13*root.scaleUnit) }
                    Row {
                        x: 24*root.scaleUnit; y: 174*root.scaleUnit; width: parent.width-48*root.scaleUnit; height: 145*root.scaleUnit; spacing: 10*root.scaleUnit
                        Repeater {
                            model: [
                                {title:"BUY", station:bridge.tradeBuyStation, system:bridge.tradeBuySystem, accent:root.amber, cmd:"trade_buy"},
                                {title:"SELL", station:bridge.tradeSellStation, system:bridge.tradeSellSystem, accent:root.green, cmd:"trade_sell"}
                            ]
                            Rectangle {
                                required property var modelData
                                width: (parent.width-parent.spacing)/2; height: parent.height; color: "#090b09"; border.color: modelData.accent; border.width: 1
                                Text { text: modelData.title+" LEG"; x: 12*root.scaleUnit; y: 10*root.scaleUnit; color: modelData.accent; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(13,16*root.scaleUnit) }
                                Text { text: modelData.station; x: 12*root.scaleUnit; y: 42*root.scaleUnit; width: parent.width-24*root.scaleUnit; color: root.whiteText; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(12,15*root.scaleUnit); elide: Text.ElideRight }
                                Text { text: modelData.system; x: 12*root.scaleUnit; y: 67*root.scaleUnit; width: parent.width-24*root.scaleUnit; color: modelData.accent; font.family: "Consolas"; font.pixelSize: Math.max(11,14*root.scaleUnit); elide: Text.ElideRight }
                                Rectangle {
                                    x:10*root.scaleUnit; y:94*root.scaleUnit
                                    width:parent.width-20*root.scaleUnit; height:50*root.scaleUnit
                                    radius:3; color:plotLegMouse.containsMouse ? "#25231d" : "#171813"
                                    border.color:plotLegMouse.containsMouse ? modelData.accent : "#6b604b"; border.width:1
                                    Rectangle { x:7*root.scaleUnit; anchors.verticalCenter:parent.verticalCenter; width:12*root.scaleUnit; height:parent.height-14*root.scaleUnit; radius:2; color:modelData.accent; opacity:.75 }
                                    Text { x:28*root.scaleUnit; anchors.verticalCenter:parent.verticalCenter; text:"PLOT "+modelData.title; color:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(12,15*root.scaleUnit) }
                                    Text { anchors.right:parent.right; anchors.rightMargin:12*root.scaleUnit; anchors.verticalCenter:parent.verticalCenter; text:"ROUTE TO "+modelData.station.toUpperCase(); color:modelData.accent; font.family:"Consolas"; font.pixelSize:Math.max(10,12*root.scaleUnit); elide:Text.ElideLeft; width:parent.width*.52; horizontalAlignment:Text.AlignRight }
                                    MouseArea { id:plotLegMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; onClicked:{ tradePage.saveProfile(); bridge.requestCommand(modelData.cmd) } }
                                }
                            }
                        }
                    }

                    Text { text: "ROUTE SOURCE"; x:24*root.scaleUnit; y:332*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,13*root.scaleUnit) }
                    Row {
                        x:24*root.scaleUnit; y:354*root.scaleUnit; width:parent.width-48*root.scaleUnit; height:64*root.scaleUnit; spacing:9*root.scaleUnit
                        MechanicalButton {
                            width:(parent.width-parent.spacing)/2; height:parent.height
                            text:"LEARN RECENT LOOP"; subtext:"USE LAST MATCHED BUY → SELL"; accent:root.whiteText
                            labelScale:.74; subtextMinSize:Math.max(11,13*root.scaleUnit)
                            onClicked:bridge.requestCommand("trade_learn_recent")
                        }
                        MechanicalButton {
                            width:(parent.width-parent.spacing)/2; height:parent.height
                            text:"CHOOSE / CHANGE ROUTE"; subtext:"OPEN ROUTE FINDER"; accent:root.whiteText
                            labelScale:.74; subtextMinSize:Math.max(11,13*root.scaleUnit)
                            onClicked:{ tradePage.selectedRouteIndex=-1; tradePage.tradeView=1 }
                        }
                    }

                    Text { text: "TRADE LOOP"; x:24*root.scaleUnit; y:426*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,13*root.scaleUnit) }
                    FlipSwitch {
                        x:24*root.scaleUnit; y:450*root.scaleUnit; width:parent.width-48*root.scaleUnit; height:72*root.scaleUnit
                        scaleUnit:root.scaleUnit
                        text:"TRADE LOOP AUTOMATION"
                        checked:bridge.tradeLoopEnabled
                        accent:root.green
                        subtext: checked
                                 ? ("ACTIVE // "+String(bridge.tradeRunLength||tradePage.runLengthValue()).toUpperCase()+" // CLICK FOR PILOT CONTROL")
                                 : ("PILOT CONTROL // "+tradePage.runLengthValue()+" READY")
                        onToggled: {
                            if (bridge.tradeLoopEnabled)
                                bridge.requestCommand("trade_pause")
                            else
                                tradePage.startRun()
                        }
                    }
                    Rectangle {
                        x:24*root.scaleUnit; y:532*root.scaleUnit; width:parent.width-48*root.scaleUnit; height:Math.max(36*root.scaleUnit, parent.height-554*root.scaleUnit); color: "#07110a"; border.color: bridge.tradeLoopEnabled ? root.green : "#263d2c"; border.width: 1
                        Text {
                            anchors.fill: parent; anchors.margins: 10*root.scaleUnit
                            text: (bridge.tradeLoopEnabled ? "AUTO LOOP ACTIVE // " : "PILOT CONTROL // ") + String(bridge.tradeLoopStatus||"-").toUpperCase()
                            color: bridge.tradeLoopEnabled ? root.green : root.whiteText
                            font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit)
                            wrapMode:Text.WordWrap; verticalAlignment:Text.AlignVCenter
                        }
                    }
                }

                MetalPanel {
                    width: parent.width*.26; height: parent.height; panelColor: root.screen
                    SectionTitle { text: "CURRENT MARKET"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }
                    Column { x:22*root.scaleUnit; y:66*root.scaleUnit; width:parent.width-44*root.scaleUnit; spacing:9*root.scaleUnit
                        Repeater { model:[
                            ["STATION",bridge.tradeMarketStation,root.whiteText],["SYSTEM",bridge.tradeMarketSystem,root.green],
                            ["COMMODITY",tradePage.selectedCommodityValue,root.whiteText],["BUY CR/T",bridge.tradeMarketBuy>0?root.fmtNumber(bridge.tradeMarketBuy):"-",root.amber],
                            ["SELL CR/T",bridge.tradeMarketSell>0?root.fmtNumber(bridge.tradeMarketSell):"-",root.green],["STOCK",root.fmtNumber(bridge.tradeMarketStock)+" T",root.amber],
                            ["DEMAND",root.fmtNumber(bridge.tradeMarketDemand)+" T",root.green]
                        ]; StatusLamp { width:parent.width; height:42*root.scaleUnit; label:modelData[0]; value:modelData[1]; stateColor:modelData[2]; phase:bridge.pulse; fontScale:1.08 } }
                    }
                }

                MetalPanel {
                    width: parent.width-tradeSetupTop.children[0].width-tradeSetupTop.children[1].width-root.gap*2; height:parent.height; panelColor:root.screen
                    SectionTitle { text:"LONG RUN / SESSION"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }
                    Column { x:22*root.scaleUnit; y:66*root.scaleUnit; width:parent.width-44*root.scaleUnit; spacing:8*root.scaleUnit
                        Repeater { model:[
                            ["RUN LENGTH",bridge.tradeRunLength,root.green],
                            ["CYCLES DONE",bridge.tradeRunTargetCycles>0?root.fmtNumber(bridge.tradeRunCompletedCycles)+" / "+root.fmtNumber(bridge.tradeRunTargetCycles):root.fmtNumber(bridge.tradeRunCompletedCycles)+" / ∞",root.green],
                            ["RUNS LEFT",bridge.tradeRunRemainingCycles>=0?root.fmtNumber(bridge.tradeRunRemainingCycles):"CONTINUOUS",root.amber],
                            ["CARGO HOLD",bridge.cargoCapacity>=0?root.fmtNumber(bridge.cargoUsed)+" / "+root.fmtNumber(bridge.cargoCapacity)+" T":root.fmtNumber(bridge.cargoUsed)+" T",root.amber],
                            ["PROFIT / CYCLE",bridge.tradeEstimatedProfitCycle>0?"~"+root.fmtNumber(bridge.tradeEstimatedProfitCycle)+" CR":"WAITING FOR DATA",root.green],
                            ["EST. REMAINING",bridge.tradeEstimatedRemainingProfit>0?"~"+root.fmtNumber(bridge.tradeEstimatedRemainingProfit)+" CR":"-",root.green],
                            ["REALIZED PROFIT",root.fmtNumber(bridge.tradeRealizedProfit)+" CR",root.green],
                            ["MERITS",bridge.tradePowerMerits>0?root.fmtNumber(bridge.tradePowerMerits):"-",root.green]
                        ]; StatusLamp { width:parent.width; height:38*root.scaleUnit; label:modelData[0]; value:modelData[1]; stateColor:modelData[2]; phase:bridge.pulse; fontScale:1.02 } }
                    }
                }
            }

            MetalPanel {
                x:0; y:tradeSetupTop.height+root.gap; width:parent.width; height:parent.height-y; panelColor:root.screen
                SectionTitle { text:"TRADE LEDGER // LIVE JOURNAL"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }
                Rectangle { x:24*root.scaleUnit; y:60*root.scaleUnit; width:parent.width-48*root.scaleUnit; height:32*root.scaleUnit; color:"#0a120d"; border.color:"#2f4c37"; border.width:1
                    Row { anchors.fill:parent; anchors.leftMargin:10*root.scaleUnit; anchors.rightMargin:10*root.scaleUnit
                        Repeater { model:["TIME","TYPE","COMMODITY","QTY","UNIT CR","PROFIT","MARGIN","LOCATION"]; Text { required property string modelData; required property int index; width:[.09,.08,.18,.08,.11,.14,.09,.23][index]*parent.width; anchors.verticalCenter:parent.verticalCenter; text:modelData; horizontalAlignment:index>=3?Text.AlignRight:Text.AlignLeft; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit) } }
                    }
                }
                ListView { id:tradeLedgerList2; x:24*root.scaleUnit; y:96*root.scaleUnit; width:parent.width-48*root.scaleUnit; height:parent.height-128*root.scaleUnit; clip:true; model:bridge.tradeLedgerRows; spacing:3*root.scaleUnit; ScrollBar.vertical:ScrollBar{policy:ScrollBar.AsNeeded}
                    delegate:Rectangle { required property var modelData; width:tradeLedgerList2.width-(tradeLedgerList2.ScrollBar.vertical.visible?14*root.scaleUnit:0); height:50*root.scaleUnit; color:index%2===0?"#08100b":"#070b08"; border.color:"#1d3828"; border.width:1
                        Row { anchors.fill:parent; anchors.leftMargin:10*root.scaleUnit; anchors.rightMargin:10*root.scaleUnit
                            Text{text:modelData.time;width:parent.width*.09;anchors.verticalCenter:parent.verticalCenter;color:root.whiteText;font.family:"Consolas";font.pixelSize:Math.max(11,14*root.scaleUnit)}
                            Text{text:modelData.type;width:parent.width*.08;anchors.verticalCenter:parent.verticalCenter;color:String(modelData.type).toUpperCase()==="SELL"?root.green:root.amber;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(11,14*root.scaleUnit)}
                            Text{text:modelData.commodity;width:parent.width*.18;anchors.verticalCenter:parent.verticalCenter;color:root.whiteText;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(11,14*root.scaleUnit);elide:Text.ElideRight}
                            Text{text:root.fmtNumber(modelData.qty);width:parent.width*.08;anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.whiteText;font.family:"Consolas";font.pixelSize:Math.max(11,14*root.scaleUnit)}
                            Text{text:root.fmtNumber(modelData.unit);width:parent.width*.11;anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.whiteText;font.family:"Consolas";font.pixelSize:Math.max(11,14*root.scaleUnit)}
                            Text{text:modelData.profit===null?"-":root.fmtNumber(modelData.profit)+" CR";width:parent.width*.14;anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:modelData.profit!==null&&Number(modelData.profit)>=0?root.green:root.red;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(11,14*root.scaleUnit)}
                            Text{text:modelData.margin;width:parent.width*.09;anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.amber;font.family:"Consolas";font.pixelSize:Math.max(11,14*root.scaleUnit)}
                            Text{text:modelData.station+" // "+modelData.system;width:parent.width*.23;anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.green;font.family:"Consolas";font.pixelSize:Math.max(11,14*root.scaleUnit);elide:Text.ElideLeft}
                        }
                    }
                    Text { anchors.centerIn:parent; visible:tradeLedgerList2.count===0; text:"NO TRADE EVENTS IN THE CURRENT JOURNAL YET"; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(14,18*root.scaleUnit) }
                }
            }
        }

        
        Popup {
            id: maxStartLyPopup
            modal: true; focus: true
            width: 240*root.scaleUnit; height: 196*root.scaleUnit
            x: Math.max(20*root.scaleUnit, tradePage.width*.27-width/2); y: 160*root.scaleUnit
            padding:0
            background: Rectangle { color:"#070b08"; border.color:root.green; border.width:2 }
            contentItem: ListView {
                clip:true
                model:tradePage.maxStartLyValues
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width:ListView.view.width; height:44*root.scaleUnit
                    color:index===tradePage.maxStartLyIndex ? "#103821" : "#08100b"
                    border.color:index===tradePage.maxStartLyIndex ? root.green : "#284332"; border.width:index===tradePage.maxStartLyIndex ? 2 : 1
                    Text { anchors.centerIn:parent; text:modelData+" LY"; color:index===tradePage.maxStartLyIndex?root.green:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(12,15*root.scaleUnit) }
                    MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked:{ tradePage.maxStartLyIndex=index; maxStartLyPopup.close() } }
                }
            }
        }
        Popup {
            id: maxLyPopup
            modal: true; focus: true
            width: 240*root.scaleUnit; height: 196*root.scaleUnit
            x: Math.max(20*root.scaleUnit, tradePage.width*.36-width/2); y: 160*root.scaleUnit
            padding:0
            background: Rectangle { color:"#070b08"; border.color:root.green; border.width:2 }
            contentItem: ListView {
                clip:true
                model:tradePage.maxLyValues
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width:ListView.view.width; height:44*root.scaleUnit
                    color:index===tradePage.maxLyIndex ? "#103821" : "#08100b"
                    border.color:index===tradePage.maxLyIndex ? root.green : "#284332"; border.width:index===tradePage.maxLyIndex ? 2 : 1
                    Text { anchors.centerIn:parent; text:modelData+" LY"; color:index===tradePage.maxLyIndex?root.green:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(12,15*root.scaleUnit) }
                    MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked:{ tradePage.maxLyIndex=index; maxLyPopup.close() } }
                }
            }
        }
        Popup {
            id: maxLsPopup
            modal: true; focus: true
            width: 260*root.scaleUnit; height: 196*root.scaleUnit
            x: Math.max(20*root.scaleUnit, tradePage.width*.50-width/2); y: 160*root.scaleUnit
            padding:0
            background: Rectangle { color:"#070b08"; border.color:root.green; border.width:2 }
            contentItem: ListView {
                clip:true
                model:tradePage.maxLsValues
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width:ListView.view.width; height:44*root.scaleUnit
                    color:index===tradePage.maxLsIndex ? "#103821" : "#08100b"
                    border.color:index===tradePage.maxLsIndex ? root.green : "#284332"; border.width:index===tradePage.maxLsIndex ? 2 : 1
                    Text { anchors.centerIn:parent; text:root.fmtNumber(modelData)+" LS"; color:index===tradePage.maxLsIndex?root.green:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(12,15*root.scaleUnit) }
                    MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked:{ tradePage.maxLsIndex=index; maxLsPopup.close() } }
                }
            }
        }
        Popup {
            id: minRunsPopup
            modal: true; focus: true
            width: 240*root.scaleUnit; height: 196*root.scaleUnit
            x: Math.max(20*root.scaleUnit, tradePage.width*.63-width/2); y: 160*root.scaleUnit
            padding:0
            background: Rectangle { color:"#070b08"; border.color:root.green; border.width:2 }
            contentItem: ListView {
                clip:true
                model:tradePage.minRunsValues
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width:ListView.view.width; height:44*root.scaleUnit
                    color:index===tradePage.minRunsIndex ? "#103821" : "#08100b"
                    border.color:index===tradePage.minRunsIndex ? root.green : "#284332"; border.width:index===tradePage.minRunsIndex ? 2 : 1
                    Text { anchors.centerIn:parent; text:modelData+" RUNS"; color:index===tradePage.minRunsIndex?root.green:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(12,15*root.scaleUnit) }
                    MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked:{ tradePage.minRunsIndex=index; minRunsPopup.close() } }
                }
            }
        }

        Popup {
            id: legalityPopup
            modal:true; focus:true
            width:300*root.scaleUnit; height:112*root.scaleUnit
            x:Math.max(20*root.scaleUnit, tradePage.width*.58-width/2); y:160*root.scaleUnit
            padding:0
            background:Rectangle{color:"#070b08";border.color:root.green;border.width:2}
            contentItem:ListView{
                clip:true; model:tradePage.legalityValues
                delegate:Rectangle{
                    required property string modelData; required property int index
                    width:ListView.view.width; height:54*root.scaleUnit
                    color:index===tradePage.legalityIndex?"#103821":"#08100b"
                    border.color:index===tradePage.legalityIndex?root.green:"#284332";border.width:index===tradePage.legalityIndex?2:1
                    Text{anchors.centerIn:parent;text:modelData;color:index===tradePage.legalityIndex?root.green:root.whiteText;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(12,15*root.scaleUnit)}
                    MouseArea{anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:{tradePage.legalityIndex=index;legalityPopup.close()}}
                }
            }
        }
        Popup {
            id: rareModePopup
            modal:true; focus:true
            width:240*root.scaleUnit; height:112*root.scaleUnit
            x:Math.max(20*root.scaleUnit, tradePage.width*.72-width/2); y:160*root.scaleUnit
            padding:0
            background:Rectangle{color:"#070b08";border.color:root.green;border.width:2}
            contentItem:ListView{
                clip:true; model:tradePage.rareModeValues
                delegate:Rectangle{
                    required property string modelData; required property int index
                    width:ListView.view.width; height:54*root.scaleUnit
                    color:index===tradePage.rareModeIndex?"#103821":"#08100b"
                    border.color:index===tradePage.rareModeIndex?root.green:"#284332";border.width:index===tradePage.rareModeIndex?2:1
                    Text{anchors.centerIn:parent;text:modelData;color:index===tradePage.rareModeIndex?root.green:root.whiteText;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(12,15*root.scaleUnit)}
                    MouseArea{anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:{tradePage.rareModeIndex=index;rareModePopup.close()}}
                }
            }
        }

// ROUTE FINDER WORKSPACE
        // TRADE WORKSPACE // ROUTE FINDER
        MetalPanel {
            visible: tradePage.tradeView===1
            x:0; y:tradeTabs.height+root.gap; width:parent.width; height:parent.height-y; panelColor:root.screen
            SectionTitle { text:"TRADE ROUTE FINDER"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }

            Row {
                id: tradeFinderControls
                x:24*root.scaleUnit; y:58*root.scaleUnit; width:parent.width-48*root.scaleUnit; height:76*root.scaleUnit; spacing:10*root.scaleUnit
                MechanicalButton { width:parent.width*.34; height:parent.height; text:tradePage.selectedCommodityValue?tradePage.selectedCommodityValue.toUpperCase():"SELECT COMMODITY"; subtext:tradePage.selectedCommodityValue?"CHANGE COMMODITY  ▼":"CHOOSE BEFORE ROUTE SEARCH  ▼"; accent:root.whiteText; showIndicator:false; labelScale:.90; subtextMinSize:Math.max(12,14*root.scaleUnit); onClicked:{tradePage.commodityQuery="";commodityPopup.open();commoditySearch.forceActiveFocus()} }
                MechanicalButton { width:parent.width*.20; height:parent.height; text:"MAX LY // "+tradePage.maxLyValues[tradePage.maxLyIndex]; subtext:"SELECT RANGE  ▼"; accent:root.whiteText; showIndicator:false; labelScale:.86; subtextMinSize:Math.max(12,14*root.scaleUnit); onClicked:maxLyPopup.open() }
                MechanicalButton { width:parent.width*.22; height:parent.height; text:"MAX LS // "+root.fmtNumber(tradePage.maxLsValues[tradePage.maxLsIndex]); subtext:"EACH STATION  ▼"; accent:root.whiteText; showIndicator:false; labelScale:.86; subtextMinSize:Math.max(12,14*root.scaleUnit); onClicked:maxLsPopup.open() }
                MechanicalButton { width:parent.width*.24-parent.spacing*3; height:parent.height; text:"MIN RUNS // "+tradePage.minRunsValues[tradePage.minRunsIndex]; subtext:"STOCK + DEMAND  ▼"; accent:root.whiteText; showIndicator:false; labelScale:.86; subtextMinSize:Math.max(12,14*root.scaleUnit); onClicked:minRunsPopup.open() }
            }
            MechanicalButton { x:24*root.scaleUnit; y:144*root.scaleUnit; width:Math.min(parent.width*.52,780*root.scaleUnit); height:72*root.scaleUnit; text:bridge.tradeRouteBusy?"SEARCHING...":"SEARCH TRADE ROUTES"; subtext:"FIND SUSTAINABLE BUY ↔ SELL LOOPS"; accent:root.green; labelScale:.88; subtextMinSize:Math.max(12,14*root.scaleUnit); onClicked:if(!bridge.tradeRouteBusy)tradePage.searchRoutes() }

            Rectangle { x:24*root.scaleUnit; y:228*root.scaleUnit; width:parent.width-48*root.scaleUnit; height:58*root.scaleUnit; color:"#07110a"; border.color:bridge.tradeRouteBusy?root.amber:"#2f4c37"; border.width:1
                Text { anchors.fill:parent; anchors.margins:10*root.scaleUnit; text:String(bridge.tradeRouteStatus||"-").toUpperCase(); color:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit); wrapMode:Text.WordWrap; verticalAlignment:Text.AlignVCenter; elide:Text.ElideRight; maximumLineCount:2 }
            }

            Rectangle { x:24*root.scaleUnit; y:298*root.scaleUnit; width:parent.width-48*root.scaleUnit; height:42*root.scaleUnit; color:"#0a120d"; border.color:"#2f4c37"; border.width:1
                Row { anchors.fill:parent; anchors.leftMargin:10*root.scaleUnit; anchors.rightMargin:10*root.scaleUnit
                    Repeater { model:["BUY MARKET","BUY CR","SUPPLY","BUY LS","SELL MARKET","SELL CR","DEMAND","SELL LS","LEG LY","PROFIT/T","PROFIT/LOAD","SCORE"]; Text { required property string modelData; required property int index; property var widths:[.155,.06,.065,.05,.155,.06,.065,.05,.05,.07,.13,.09]; width:widths[index]*parent.width; anchors.verticalCenter:parent.verticalCenter; text:modelData; horizontalAlignment:index===0||index===4?Text.AlignLeft:Text.AlignRight; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,13*root.scaleUnit) } }
                }
            }
            ListView {
                id: tradeRouteList; x:24*root.scaleUnit; y:344*root.scaleUnit; width:parent.width-48*root.scaleUnit; height:parent.height-442*root.scaleUnit; clip:true; model:bridge.tradeRouteRows; spacing:3*root.scaleUnit
                ScrollBar.vertical:ScrollBar{policy:ScrollBar.AlwaysOn}
                delegate: Rectangle {
                    id: routeResultRow
                    required property var modelData; required property int index
                    width:tradeRouteList.width-(tradeRouteList.ScrollBar.vertical.visible?14*root.scaleUnit:0); height:56*root.scaleUnit
                    color: tradePage.selectedRouteIndex===index ? "#103821" : (routeResultMouse.pressed ? "#173823" : (routeResultMouse.containsMouse ? "#10281a" : (index%2===0?"#08100b":"#070b08")))
                    border.color: tradePage.selectedRouteIndex===index ? root.green : (routeResultMouse.containsMouse ? "#6f956f" : "#1d3828")
                    border.width: tradePage.selectedRouteIndex===index ? 2 : (routeResultMouse.containsMouse ? 2 : 1)
                    Row { anchors.fill:parent; anchors.leftMargin:10*root.scaleUnit; anchors.rightMargin:10*root.scaleUnit
                        property var widths:[.155,.06,.065,.05,.155,.06,.065,.05,.05,.07,.13,.09]
                        Item { width:parent.width*parent.widths[0]; height:parent.height; Text{text:modelData.buyStation; x:0; y:8*root.scaleUnit; width:parent.width; color:root.amber;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(10,13*root.scaleUnit);elide:Text.ElideRight} Text{text:modelData.buySystem; x:0;y:29*root.scaleUnit;width:parent.width;color:root.whiteText;font.family:"Consolas";font.pixelSize:Math.max(10,11*root.scaleUnit);elide:Text.ElideRight} }
                        Text{text:root.fmtNumber(modelData.buyPrice);width:parent.width*parent.widths[1];anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.amber;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(10,13*root.scaleUnit)}
                        Text{text:root.fmtNumber(modelData.supply);width:parent.width*parent.widths[2];anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.whiteText;font.family:"Consolas";font.pixelSize:Math.max(10,12*root.scaleUnit)}
                        Text{text:root.fmtNumber(modelData.buyLs);width:parent.width*parent.widths[3];anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.green;font.family:"Consolas";font.pixelSize:Math.max(10,12*root.scaleUnit)}
                        Item { width:parent.width*parent.widths[4]; height:parent.height; Text{text:modelData.sellStation; x:0;y:8*root.scaleUnit;width:parent.width;color:root.green;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(10,13*root.scaleUnit);elide:Text.ElideRight} Text{text:modelData.sellSystem; x:0;y:29*root.scaleUnit;width:parent.width;color:root.whiteText;font.family:"Consolas";font.pixelSize:Math.max(10,11*root.scaleUnit);elide:Text.ElideRight} }
                        Text{text:root.fmtNumber(modelData.sellPrice);width:parent.width*parent.widths[5];anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.green;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(10,13*root.scaleUnit)}
                        Text{text:root.fmtNumber(modelData.demand);width:parent.width*parent.widths[6];anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.whiteText;font.family:"Consolas";font.pixelSize:Math.max(10,12*root.scaleUnit)}
                        Text{text:root.fmtNumber(modelData.sellLs);width:parent.width*parent.widths[7];anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.green;font.family:"Consolas";font.pixelSize:Math.max(10,12*root.scaleUnit)}
                        Text{text:Number(modelData.legLy).toFixed(1);width:parent.width*parent.widths[8];anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.whiteText;font.family:"Consolas";font.pixelSize:Math.max(10,12*root.scaleUnit)}
                        Text{text:root.fmtNumber(modelData.profitPerT);width:parent.width*parent.widths[9];anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.green;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(10,13*root.scaleUnit)}
                        Text{text:root.fmtNumber(modelData.profitPerLoad);width:parent.width*parent.widths[10];anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.green;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(11,14*root.scaleUnit)}
                        Text{text:Number(modelData.score||0).toFixed(1);width:parent.width*parent.widths[11];anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:Number(modelData.score||0)>=90?root.green:root.amber;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(11,14*root.scaleUnit)}
                    }
                    MouseArea { id: routeResultMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; onClicked:tradePage.selectedRouteIndex=index; onDoubleClicked:{tradePage.selectedRouteIndex=index;bridge.useTradeRouteIndex(index);tradePage.tradeView=0} }
                }
                Text { anchors.centerIn:parent; visible:tradeRouteList.count===0&&!bridge.tradeRouteBusy; text:"NO ROUTE RESULTS YET // SELECT A COMMODITY AND FIND ROUTES"; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(14,18*root.scaleUnit) }
            }
            Row {
                id: tradeFinderBottomActions
                x:24*root.scaleUnit; y:parent.height-86*root.scaleUnit; width:parent.width-48*root.scaleUnit; height:70*root.scaleUnit; spacing:10*root.scaleUnit
                Item { width:parent.width*.54; height:parent.height
                    MechanicalButton { anchors.fill:parent; text:"USE SELECTED ROUTE AS LOOP"; subtext:tradePage.selectedRouteIndex>=0?"LOAD ROUTE + OPEN TRADE LOOP":"SELECT A RESULT FIRST"; accent:tradePage.selectedRouteIndex>=0?root.green:root.muted; labelScale:.96; subtextMinSize:Math.max(12,14*root.scaleUnit); onClicked:if(tradePage.selectedRouteIndex>=0){bridge.useTradeRouteIndex(tradePage.selectedRouteIndex);tradePage.selectedRouteIndex=-1;tradePage.tradeView=0} }
                    Rectangle { anchors.fill:parent; anchors.margins:-4*root.scaleUnit; visible:tradePage.selectedRouteIndex>=0; color:"transparent"; border.color:root.amber; border.width:Math.max(2,3*root.scaleUnit); SequentialAnimation on opacity{running:parent.visible;loops:Animation.Infinite;NumberAnimation{to:.28;duration:420}
                                NumberAnimation{to:1;duration:420}} }
                }
                MechanicalButton { width:parent.width*.22; height:parent.height; text:"REFRESH"; subtext:"RUN SEARCH AGAIN"; accent:root.amber; labelScale:.92; subtextMinSize:Math.max(12,13*root.scaleUnit); onClicked:tradePage.searchRoutes() }
                MechanicalButton { width:parent.width*.24-parent.spacing*2; height:parent.height; text:"BACK TO TRADE LOOP"; subtext:"KEEP CURRENT ROUTE"; accent:root.whiteText; labelScale:.82; subtextMinSize:Math.max(12,13*root.scaleUnit); onClicked:tradePage.tradeView=0 }
            }
        }

        // BEST TRADE WORKSPACE: broad commodity optimizer. Trade Loop and Route Finder remain separate, explicit stages.
        MetalPanel {
            visible: tradePage.tradeView===2
            x:0; y:tradeTabs.height+root.gap; width:parent.width; height:parent.height-y; panelColor:root.screen
            SectionTitle { text:"BEST TRADE // ALL COMMODITIES"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }

            Row {
                id: bestTradeFilters
                x:24*root.scaleUnit; y:58*root.scaleUnit; width:parent.width-48*root.scaleUnit; height:82*root.scaleUnit; spacing:10*root.scaleUnit

                // Passive telemetry, deliberately NOT a button. No hover, click, or pressed state.
                Rectangle {
                    width:parent.width*.13; height:parent.height; radius:3*root.scaleUnit
                    color:"#070a08"; border.color:"#475348"; border.width:1
                    Rectangle { anchors.fill:parent; anchors.margins:5*root.scaleUnit; radius:2*root.scaleUnit; color:"#09100b"; border.color:"#25382c"; border.width:1 }
                    Text {
                        x:14*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-28*root.scaleUnit
                        text:root.fmtNumber(bridge.cargoCapacity>0?bridge.cargoCapacity:bridge.tradePlannedCargo)+" T"
                        color:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(14,19*root.scaleUnit); elide:Text.ElideRight
                    }
                    Text {
                        x:14*root.scaleUnit; y:47*root.scaleUnit; width:parent.width-28*root.scaleUnit
                        text:"SHIP CARGO // AUTO"; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,13*root.scaleUnit); elide:Text.ElideRight
                    }
                }
                MechanicalButton { width:parent.width*.12; height:parent.height; text:"MAX START LY // "+tradePage.maxStartLyValues[tradePage.maxStartLyIndex]; subtext:"YOU → BUY  ▼"; accent:root.amber; labelScale:.76; subtextMinSize:Math.max(11,13*root.scaleUnit); onClicked:maxStartLyPopup.open() }
                MechanicalButton { width:parent.width*.12; height:parent.height; text:"MAX LEG LY // "+tradePage.maxLyValues[tradePage.maxLyIndex]; subtext:"BUY → SELL  ▼"; accent:root.amber; labelScale:.76; subtextMinSize:Math.max(11,13*root.scaleUnit); onClicked:maxLyPopup.open() }
                MechanicalButton { width:parent.width*.13; height:parent.height; text:"MAX LS // "+root.fmtNumber(tradePage.maxLsValues[tradePage.maxLsIndex]); subtext:"EACH STATION  ▼"; accent:root.amber; labelScale:.80; subtextMinSize:Math.max(11,13*root.scaleUnit); onClicked:maxLsPopup.open() }
                MechanicalButton { width:parent.width*.12; height:parent.height; text:"MIN RUNS // "+tradePage.minRunsValues[tradePage.minRunsIndex]; subtext:"SUSTAINABILITY  ▼"; accent:root.whiteText; labelScale:.78; subtextMinSize:Math.max(11,13*root.scaleUnit); onClicked:minRunsPopup.open() }
                MechanicalButton {
                    width:parent.width*.20; height:parent.height
                    text:tradePage.legalityValues[tradePage.legalityIndex]
                    subtext:tradePage.legalityIndex===1 ? "RESTRICTED CARGO RISK  ▼" : "LEGALITY FILTER  ▼"
                    accent:tradePage.legalityIndex===1 ? root.red : root.whiteText
                    stateful:true
                    active:tradePage.legalityIndex===1
                    showIndicator:tradePage.legalityIndex===1
                    labelScale:.82; subtextMinSize:Math.max(11,13*root.scaleUnit)
                    onClicked:legalityPopup.open()
                }
                MechanicalButton { width:parent.width*.18-parent.spacing*6; height:parent.height; text:"RARE // "+tradePage.rareModeValues[tradePage.rareModeIndex]; subtext:"RARE GOODS  ▼"; accent:root.green; labelScale:.80; subtextMinSize:Math.max(11,13*root.scaleUnit); onClicked:rareModePopup.open() }
            }

            MechanicalButton {
                id: bestTradeSearchButton
                x:24*root.scaleUnit; y:152*root.scaleUnit; width:parent.width-48*root.scaleUnit; height:84*root.scaleUnit
                busyPulse: bridge.tradeBestBusy
                actionFlashColor: root.green
                text:bridge.tradeBestBusy?"SCANNING GALAXY MARKETS...":"FIND BEST TRADE"
                subtext:"SEARCH ALL COMMODITIES // RANK THE BEST ROUTES"
                accent:bridge.tradeBestBusy?root.amber:root.green; labelScale:1.08; subtextMinSize:Math.max(13,16*root.scaleUnit)
                onClicked:if(!bridge.tradeBestBusy)tradePage.searchBestTrade()
            }

            Rectangle {
                x:24*root.scaleUnit; y:248*root.scaleUnit; width:parent.width-48*root.scaleUnit; height:58*root.scaleUnit
                color:"#07110a"; border.color:bridge.tradeBestBusy?root.amber:"#2f4c37"; border.width:1
                Text { anchors.fill:parent; anchors.margins:10*root.scaleUnit; text:String(bridge.tradeBestStatus||"-").toUpperCase(); color:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit); wrapMode:Text.WordWrap; verticalAlignment:Text.AlignVCenter; elide:Text.ElideRight; maximumLineCount:2 }
            }

            Rectangle {
                x:24*root.scaleUnit; y:318*root.scaleUnit; width:parent.width-48*root.scaleUnit; height:42*root.scaleUnit; color:"#0a120d"; border.color:"#2f4c37"; border.width:1
                Row { anchors.fill:parent; anchors.leftMargin:10*root.scaleUnit; anchors.rightMargin:10*root.scaleUnit
                    Repeater {
                        model:["SCORE / COMMODITY","BUY MARKET","START LY","BUY CR","SUPPLY","BUY LS","SELL MARKET","SELL CR","DEMAND","SELL LS","LEG LY","PROFIT/T","PROFIT/LOAD"]
                        Text { required property string modelData; required property int index; property var widths:[.12,.15,.055,.06,.055,.045,.15,.06,.055,.045,.05,.065,.09]; width:widths[index]*parent.width; anchors.verticalCenter:parent.verticalCenter; text:modelData; horizontalAlignment:index===0||index===1||index===6?Text.AlignLeft:Text.AlignRight; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,12*root.scaleUnit) }
                    }
                }
            }

            ListView {
                id: bestTradeList; x:24*root.scaleUnit; y:364*root.scaleUnit; width:parent.width-48*root.scaleUnit; height:parent.height-462*root.scaleUnit; clip:true; model:bridge.tradeBestRows; spacing:3*root.scaleUnit
                ScrollBar.vertical:ScrollBar{policy:ScrollBar.AlwaysOn}
                delegate:Rectangle {
                    id: bestTradeResultRow
                    required property var modelData; required property int index
                    width:bestTradeList.width-(bestTradeList.ScrollBar.vertical.visible?14*root.scaleUnit:0); height:62*root.scaleUnit
                    color: tradePage.selectedBestRouteIndex===index ? "#103821" : (bestTradeResultMouse.pressed ? "#173823" : (bestTradeResultMouse.containsMouse ? "#10281a" : (index%2===0?"#08100b":"#070b08")))
                    border.color: tradePage.selectedBestRouteIndex===index ? root.green : (bestTradeResultMouse.containsMouse ? "#6f956f" : "#1d3828")
                    border.width: tradePage.selectedBestRouteIndex===index ? 2 : (bestTradeResultMouse.containsMouse ? 2 : 1)
                    Row { anchors.fill:parent; anchors.leftMargin:10*root.scaleUnit; anchors.rightMargin:10*root.scaleUnit; property var widths:[.12,.15,.055,.06,.055,.045,.15,.06,.055,.045,.05,.065,.09]
                        Item { width:parent.width*parent.widths[0]; height:parent.height
                            Text{text:Number(modelData.score||0).toFixed(1);x:0;y:7*root.scaleUnit;width:parent.width;color:Number(modelData.score||0)>=90?root.green:root.amber;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(13,17*root.scaleUnit)}
                            Text{text:String(modelData.commodity||"-").toUpperCase();x:0;y:33*root.scaleUnit;width:parent.width;color:root.whiteText;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(10,11*root.scaleUnit);elide:Text.ElideRight}
                        }
                        Item { width:parent.width*parent.widths[1]; height:parent.height; Text{text:modelData.buyStation;x:0;y:8*root.scaleUnit;width:parent.width;color:root.amber;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(10,13*root.scaleUnit);elide:Text.ElideRight} Text{text:modelData.buySystem;x:0;y:32*root.scaleUnit;width:parent.width;color:root.whiteText;font.family:"Consolas";font.pixelSize:Math.max(10,11*root.scaleUnit);elide:Text.ElideRight} }
                        Text{text:modelData.startLy===null||modelData.startLy===undefined?"?":Number(modelData.startLy).toFixed(1);width:parent.width*parent.widths[2];anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.amber;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(10,12*root.scaleUnit)}
                        Text{text:root.fmtNumber(modelData.buyPrice);width:parent.width*parent.widths[3];anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.amber;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(10,12*root.scaleUnit)}
                        Text{text:root.fmtNumber(modelData.supply);width:parent.width*parent.widths[4];anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.whiteText;font.family:"Consolas";font.pixelSize:Math.max(10,12*root.scaleUnit)}
                        Text{text:root.fmtNumber(modelData.buyLs);width:parent.width*parent.widths[5];anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.green;font.family:"Consolas";font.pixelSize:Math.max(10,12*root.scaleUnit)}
                        Item { width:parent.width*parent.widths[6]; height:parent.height; Text{text:modelData.sellStation;x:0;y:8*root.scaleUnit;width:parent.width;color:root.green;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(10,13*root.scaleUnit);elide:Text.ElideRight} Text{text:modelData.sellSystem;x:0;y:32*root.scaleUnit;width:parent.width;color:root.whiteText;font.family:"Consolas";font.pixelSize:Math.max(10,11*root.scaleUnit);elide:Text.ElideRight} }
                        Text{text:root.fmtNumber(modelData.sellPrice);width:parent.width*parent.widths[7];anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.green;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(10,12*root.scaleUnit)}
                        Text{text:root.fmtNumber(modelData.demand);width:parent.width*parent.widths[8];anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.whiteText;font.family:"Consolas";font.pixelSize:Math.max(10,12*root.scaleUnit)}
                        Text{text:root.fmtNumber(modelData.sellLs);width:parent.width*parent.widths[9];anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.green;font.family:"Consolas";font.pixelSize:Math.max(10,12*root.scaleUnit)}
                        Text{text:Number(modelData.legLy||0).toFixed(1);width:parent.width*parent.widths[10];anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.whiteText;font.family:"Consolas";font.pixelSize:Math.max(10,12*root.scaleUnit)}
                        Text{text:root.fmtNumber(modelData.profitPerT);width:parent.width*parent.widths[11];anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.green;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(10,12*root.scaleUnit)}
                        Text{text:root.fmtNumber(modelData.profitPerLoad);width:parent.width*parent.widths[12];anchors.verticalCenter:parent.verticalCenter;horizontalAlignment:Text.AlignRight;color:root.green;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(11,14*root.scaleUnit)}
                    }
                    MouseArea { id: bestTradeResultMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; onClicked:tradePage.selectedBestRouteIndex=index; onDoubleClicked:{tradePage.selectedBestRouteIndex=index;tradePage.selectedCommodityValue=String(modelData.commodity||tradePage.selectedCommodityValue);bridge.useBestTradeIndex(index);tradePage.tradeView=0} }
                }
                Text { anchors.centerIn:parent; visible:bestTradeList.count===0&&!bridge.tradeBestBusy; text:"NO BEST-TRADE RESULTS YET // PRESS FIND BEST TRADE"; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(14,18*root.scaleUnit) }
            }

            Row {
                id: bestTradeBottomActions
                x:24*root.scaleUnit; y:parent.height-86*root.scaleUnit; width:parent.width-48*root.scaleUnit; height:70*root.scaleUnit; spacing:10*root.scaleUnit
                Item { width:parent.width*.54; height:parent.height
                    MechanicalButton { anchors.fill:parent; text:"USE SELECTED BEST LOOP"; subtext:tradePage.selectedBestRouteIndex>=0?"LOAD COMMODITY + BUY + SELL STATIONS":"SELECT A RESULT FIRST"; accent:tradePage.selectedBestRouteIndex>=0?root.green:root.muted; labelScale:.92; subtextMinSize:Math.max(12,14*root.scaleUnit); onClicked:if(tradePage.selectedBestRouteIndex>=0){var r=bridge.tradeBestRows[tradePage.selectedBestRouteIndex];if(r)tradePage.selectedCommodityValue=String(r.commodity||tradePage.selectedCommodityValue);bridge.useBestTradeIndex(tradePage.selectedBestRouteIndex);tradePage.selectedBestRouteIndex=-1;tradePage.tradeView=0} }
                    Rectangle { anchors.fill:parent; anchors.margins:-4*root.scaleUnit; visible:tradePage.selectedBestRouteIndex>=0; color:"transparent"; border.color:root.amber; border.width:Math.max(2,3*root.scaleUnit); SequentialAnimation on opacity{running:parent.visible;loops:Animation.Infinite;NumberAnimation{to:.28;duration:420} NumberAnimation{to:1;duration:420}} }
                }
                MechanicalButton { width:parent.width*.22; height:parent.height; text:"SEARCH AGAIN"; subtext:"RESCAN COMMODITIES"; accent:root.amber; labelScale:.90; subtextMinSize:Math.max(12,13*root.scaleUnit); onClicked:if(!bridge.tradeBestBusy)tradePage.searchBestTrade() }
                MechanicalButton { width:parent.width*.24-parent.spacing*2; height:parent.height; text:"BACK TO TRADE LOOP"; subtext:"KEEP CURRENT ROUTE"; accent:root.whiteText; labelScale:.82; subtextMinSize:Math.max(12,13*root.scaleUnit); onClicked:tradePage.tradeView=0 }
            }
        }
    }

    // COLONIZATION MODULE: project logistics and construction progress.
    // Commodity sourcing is intentionally handed to the existing Trade Route Finder.
    Item {
        id: colonizationPage
        visible: root.currentPage === 4
        x: identity.x
        y: identity.y + identity.height + root.gap
        width: identity.width
        height: root.height - y - root.m
        property string selectedRequirementName: ""

        function activeRequirement() {
            var rows = bridge.colonizationRequirementRows
            if (!rows || rows.length === 0) return null
            if (selectedRequirementName !== "") {
                for (var i=0; i<rows.length; ++i) {
                    if (String(rows[i].name || "") === selectedRequirementName) return rows[i]
                }
            }
            return rows[0]
        }
        function activeCommodity() {
            var row = activeRequirement()
            return row ? String(row.name || "-") : "-"
        }
        function activeRemaining() {
            var row = activeRequirement()
            return row ? Number(row.remaining || 0) : 0
        }
        function activeAboard() {
            var row = activeRequirement()
            return row ? Number(row.aboard || 0) : 0
        }
        function activeLoadTarget() {
            var need = activeRemaining()
            var cap = Number(bridge.cargoCapacity || 0)
            return cap > 0 ? Math.min(need, cap) : need
        }
        function activePurchaseTarget() {
            var target = activeLoadTarget()
            var aboard = Math.min(target, activeAboard())
            var free = Number(bridge.cargoCapacity || 0) > 0 ? Math.max(0, Number(bridge.cargoCapacity || 0)-Number(bridge.cargoUsed || 0)) : Math.max(0,target-aboard)
            return Math.max(0, Math.min(target-aboard, free))
        }
        function findSelectedSupply() {
            var row = activeRequirement()
            var purchaseTarget = activePurchaseTarget()
            if (!row || Number(row.remaining || 0) <= 0 || purchaseTarget <= 0) return
            tradePage.selectedCommodityValue = String(row.name || "")
            tradePage.selectedRouteIndex = -1
            tradePage.minRunsIndex = 0
            tradePage.tradeView = 1
            bridge.searchColonizationSupply(
                String(row.name || ""),
                Number(purchaseTarget),
                String(tradePage.maxLyValues[tradePage.maxLyIndex]),
                String(tradePage.maxLsValues[tradePage.maxLsIndex]),
                "1"
            )
            root.currentPage = 3
        }

        Popup {
            id: colonyProjectPopup
            modal: true; focus: true
            x: Math.max(20*root.scaleUnit, (colonizationPage.width-width)/2)
            y: 78*root.scaleUnit
            width: Math.min(760*root.scaleUnit, colonizationPage.width-40*root.scaleUnit)
            height: Math.min(620*root.scaleUnit, colonizationPage.height-100*root.scaleUnit)
            padding: 0
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
            background: Rectangle { color: "#070b08"; border.color: root.green; border.width: 2 }
            contentItem: Item {
                Text { text: "SELECT SAVED CONSTRUCTION PROJECT"; x: 20*root.scaleUnit; y: 18*root.scaleUnit; color: root.green; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(15,20*root.scaleUnit) }
                Text { text: "SAVED PROJECTS ARE RESTORED FROM ELITE JOURNAL DATA"; x: 20*root.scaleUnit; y: 48*root.scaleUnit; width: parent.width-40*root.scaleUnit; color: root.muted; font.family: "Consolas"; font.pixelSize: Math.max(10,13*root.scaleUnit); elide: Text.ElideRight }
                ListView {
                    id: colonyProjectList
                    x: 20*root.scaleUnit; y: 82*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: parent.height-102*root.scaleUnit
                    clip: true; spacing: 3*root.scaleUnit; model: bridge.colonizationProjectRows
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: colonyProjectList.width-(colonyProjectList.ScrollBar.vertical.visible?14*root.scaleUnit:0); height: 68*root.scaleUnit
                        color: bridge.colonizationCurrentProjectIndex===index ? "#123a23" : (projectMouse.containsMouse ? "#102619" : (index%2===0?"#08100b":"#060a07"))
                        border.color: bridge.colonizationCurrentProjectIndex===index ? root.green : (projectMouse.containsMouse?root.amber:"#23372a")
                        border.width: bridge.colonizationCurrentProjectIndex===index ? 2 : 1
                        Text { text: String(modelData.station||"-"); x: 12*root.scaleUnit; y: 8*root.scaleUnit; width: parent.width*.46; color: root.whiteText; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(12,16*root.scaleUnit); elide: Text.ElideRight }
                        Text { text: String(modelData.system||"-"); x: 12*root.scaleUnit; y: 34*root.scaleUnit; width: parent.width*.46; color: root.muted; font.family: "Consolas"; font.pixelSize: Math.max(10,13*root.scaleUnit); elide: Text.ElideRight }
                        Text { text: String(modelData.status||"ACTIVE")+" // "+Number(modelData.progressPct||0).toFixed(1)+"%"; x: parent.width*.50; y: 8*root.scaleUnit; width: parent.width*.23; color: String(modelData.status)==="FAILED"?root.red:(String(modelData.status)==="COMPLETE"?root.green:root.amber); font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(11,14*root.scaleUnit); horizontalAlignment: Text.AlignRight }
                        Text { text: root.fmtNumber(modelData.remaining||0)+" T LEFT"; x: parent.width*.75; y: 8*root.scaleUnit; width: parent.width*.22; color: root.green; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(11,14*root.scaleUnit); horizontalAlignment: Text.AlignRight }
                        Text { text: "MARKET ID // "+String(modelData.marketId||"-"); x: parent.width*.50; y: 34*root.scaleUnit; width: parent.width*.47; color: root.muted; font.family: "Consolas"; font.pixelSize: Math.max(10,12*root.scaleUnit); horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
                        MouseArea { id: projectMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { bridge.useColonizationProjectIndex(index); colonizationPage.selectedRequirementName=""; colonyProjectPopup.close() } }
                    }
                }
            }
        }

        Row {
            id: colonyTop
            width: parent.width
            height: parent.height * .61
            spacing: root.gap

            MetalPanel {
                id: projectOverview
                width: colonyTop.width * .30
                height: colonyTop.height
                panelColor: root.screen
                SectionTitle { text: "PROJECT OVERVIEW"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }

                MechanicalButton {
                    x: 22*root.scaleUnit; y: 62*root.scaleUnit; width: parent.width-44*root.scaleUnit; height: 76*root.scaleUnit
                    text: bridge.colonizationHasProject ? bridge.colonizationStation : "NO CONSTRUCTION PROJECT"
                    subtext: bridge.colonizationHasProject ? (bridge.colonizationSystem+" // "+bridge.colonizationProjectRows.length+" SAVED PROJECT"+(bridge.colonizationProjectRows.length===1?"":"S")) : "DOCK AT A CONSTRUCTION DEPOT TO SEED PROJECT DATA"
                    accent: bridge.colonizationHasProject ? root.green : root.amber
                    labelScale: .78; subtextMinSize: Math.max(10,12*root.scaleUnit)
                    onClicked: if (bridge.colonizationProjectRows.length>0) colonyProjectPopup.open()
                }

                Text { text: bridge.colonizationStatus; x: 28*root.scaleUnit; y: 158*root.scaleUnit; color: bridge.colonizationStatus==="FAILED"?root.red:(bridge.colonizationStatus==="COMPLETE"?root.green:root.amber); font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(14,19*root.scaleUnit) }
                Text { text: Number(bridge.colonizationProgressPercent||0).toFixed(1)+"%"; anchors.right: parent.right; anchors.rightMargin: 28*root.scaleUnit; y: 154*root.scaleUnit; color: root.green; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(18,25*root.scaleUnit) }
                Rectangle {
                    x: 28*root.scaleUnit; y: 190*root.scaleUnit; width: parent.width-56*root.scaleUnit; height: 18*root.scaleUnit
                    color: "#050805"; border.color: "#274331"; border.width: 1
                    Rectangle { x: 2; y: 2; height: parent.height-4; width: Math.max(0,(parent.width-4)*Math.min(100,Math.max(0,bridge.colonizationProgressPercent))/100); color: bridge.colonizationStatus==="FAILED"?root.red:root.green; opacity: .78 }
                }

                Column {
                    x: 28*root.scaleUnit; y: 232*root.scaleUnit; width: parent.width-56*root.scaleUnit; spacing: 11*root.scaleUnit
                    Repeater {
                        model: [
                            ["OUTSTANDING",root.fmtNumber(bridge.colonizationRemainingTotal)+" T",root.green],
                            ["COMMODITIES",bridge.colonizationCompleteCount+" COMPLETE / "+bridge.colonizationIncompleteCount+" OPEN",root.whiteText],
                            ["YOUR JOURNAL DELIVERY",root.fmtNumber(bridge.colonizationContributionTotal)+" T",root.amber],
                            ["SHIP CARGO",(bridge.cargoCapacity>0?root.fmtNumber(bridge.cargoCapacity)+" T CAPACITY":"UNKNOWN"),root.whiteText],
                            ["MARKET ID",bridge.colonizationMarketId,root.muted],
                            ["LAST UPDATE",bridge.colonizationLastUpdate,root.muted]
                        ]
                        Item {
                            width: parent.width; height: 31*root.scaleUnit
                            Text { text: modelData[0]; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; color: root.muted; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,13*root.scaleUnit) }
                            Text { text: modelData[1]; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: parent.width*.62; horizontalAlignment: Text.AlignRight; color: modelData[2]; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(11,14*root.scaleUnit); elide: Text.ElideRight }
                        }
                    }
                }

                Rectangle { x: 28*root.scaleUnit; y: parent.height-108*root.scaleUnit; width: parent.width-56*root.scaleUnit; height: 1; color: "#294331" }
                Text { text: "HAULING PACE"; x: 28*root.scaleUnit; y: parent.height-92*root.scaleUnit; color: root.muted; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,13*root.scaleUnit) }
                Text { text: bridge.colonizationPaceText; x: 28*root.scaleUnit; y: parent.height-70*root.scaleUnit; width: parent.width-56*root.scaleUnit; height: 52*root.scaleUnit; color: root.whiteText; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,13*root.scaleUnit); wrapMode: Text.WordWrap; elide: Text.ElideRight; maximumLineCount: 3 }
            }

            MetalPanel {
                id: supplyPanel
                width: colonyTop.width * .45
                height: colonyTop.height
                panelColor: root.screen
                SectionTitle { text: "CONSTRUCTION REQUIREMENTS"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }
                Text { text: "SITE PROVIDED = ALL COMMANDERS // ABOARD = YOUR CURRENT SHIP"; x: 24*root.scaleUnit; y: 51*root.scaleUnit; width: parent.width-48*root.scaleUnit; color: root.muted; font.family: "Consolas"; font.pixelSize: Math.max(10,11*root.scaleUnit); elide: Text.ElideRight }

                Row {
                    x: 22*root.scaleUnit; y: 79*root.scaleUnit; width: parent.width-44*root.scaleUnit; height: 26*root.scaleUnit
                    Text { text: "COMMODITY"; width: parent.width*.36; color: "#708078"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,13*root.scaleUnit) }
                    Text { text: "REQUIRED"; width: parent.width*.14; color: "#708078"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,13*root.scaleUnit); horizontalAlignment: Text.AlignRight }
                    Text { text: "PROVIDED"; width: parent.width*.14; color: "#708078"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,13*root.scaleUnit); horizontalAlignment: Text.AlignRight }
                    Text { text: "LEFT"; width: parent.width*.14; color: "#708078"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,13*root.scaleUnit); horizontalAlignment: Text.AlignRight }
                    Text { text: "ABOARD"; width: parent.width*.12; color: "#708078"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,13*root.scaleUnit); horizontalAlignment: Text.AlignRight }
                    Text { text: "STATE"; width: parent.width*.10; color: "#708078"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,13*root.scaleUnit); horizontalAlignment: Text.AlignRight }
                }

                ListView {
                    id: colonyRequirementList
                    x: 22*root.scaleUnit; y: 110*root.scaleUnit; width: parent.width-44*root.scaleUnit; height: parent.height-151*root.scaleUnit
                    clip: true; spacing: 3*root.scaleUnit; model: bridge.colonizationRequirementRows
                                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: colonyRequirementList.width-(colonyRequirementList.ScrollBar.vertical.visible?14*root.scaleUnit:0); height: 47*root.scaleUnit
                        color: colonizationPage.selectedRequirementName===String(modelData.name||"") ? "#123a23" : (requirementMouse.containsMouse?"#102619":(index%2===0?"#080a08":"#070907"))
                        border.color: colonizationPage.selectedRequirementName===String(modelData.name||"") ? root.green : (requirementMouse.containsMouse?root.amber:"#202a23")
                        border.width: colonizationPage.selectedRequirementName===String(modelData.name||"") ? 2 : 1
                        Row {
                            anchors.fill: parent; anchors.leftMargin: 10*root.scaleUnit; anchors.rightMargin: 10*root.scaleUnit
                            Text { text: String(modelData.name||"-"); width: parent.width*.36; anchors.verticalCenter: parent.verticalCenter; color: modelData.complete?root.muted:root.whiteText; font.family: "Consolas"; font.bold: !modelData.complete; font.pixelSize: Math.max(11,14*root.scaleUnit); elide: Text.ElideRight }
                            Text { text: root.fmtNumber(modelData.required||0); width: parent.width*.14; anchors.verticalCenter: parent.verticalCenter; color: root.whiteText; font.family: "Consolas"; font.pixelSize: Math.max(10,13*root.scaleUnit); horizontalAlignment: Text.AlignRight }
                            Text { text: root.fmtNumber(modelData.provided||0); width: parent.width*.14; anchors.verticalCenter: parent.verticalCenter; color: root.whiteText; font.family: "Consolas"; font.pixelSize: Math.max(10,13*root.scaleUnit); horizontalAlignment: Text.AlignRight }
                            Text { text: root.fmtNumber(modelData.remaining||0); width: parent.width*.14; anchors.verticalCenter: parent.verticalCenter; color: modelData.complete?root.green:root.amber; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,13*root.scaleUnit); horizontalAlignment: Text.AlignRight }
                            Text { text: root.fmtNumber(modelData.aboard||0); width: parent.width*.12; anchors.verticalCenter: parent.verticalCenter; color: Number(modelData.aboard||0)>0?root.green:root.muted; font.family: "Consolas"; font.bold: Number(modelData.aboard||0)>0; font.pixelSize: Math.max(10,13*root.scaleUnit); horizontalAlignment: Text.AlignRight }
                            Text { text: modelData.complete?"DONE":"NEEDED"; width: parent.width*.10; anchors.verticalCenter: parent.verticalCenter; color: modelData.complete?root.green:root.amber; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,11*root.scaleUnit); horizontalAlignment: Text.AlignRight }
                        }
                        MouseArea { id: requirementMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: colonizationPage.selectedRequirementName=String(modelData.name||""); onDoubleClicked: { colonizationPage.selectedRequirementName=String(modelData.name||""); if (!modelData.complete) colonizationPage.findSelectedSupply() } }
                    }
                }
                Text { anchors.centerIn: colonyRequirementList; visible: colonyRequirementList.count===0; text: bridge.colonizationHasProject?"NO REQUIREMENT ROWS IN LAST PROJECT SNAPSHOT":"NO CONSTRUCTION PROJECT OBSERVED YET"; color: root.muted; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(12,15*root.scaleUnit) }
                Text { text: "SELECT A ROW TO PLAN THAT COMMODITY // DOUBLE-CLICK TO FIND SUPPLY"; x: 22*root.scaleUnit; y: parent.height-32*root.scaleUnit; width: parent.width-44*root.scaleUnit; color: root.muted; font.family: "Consolas"; font.pixelSize: Math.max(10,11*root.scaleUnit); elide: Text.ElideRight }
            }

            MetalPanel {
                id: nextDeliveryPanel
                width: colonyTop.width - projectOverview.width - supplyPanel.width - root.gap*2
                height: colonyTop.height
                panelColor: root.screen
                SectionTitle { text: "NEXT DELIVERY"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }

                Text { text: colonizationPage.activeCommodity(); x: 24*root.scaleUnit; y: 72*root.scaleUnit; width: parent.width-48*root.scaleUnit; color: root.green; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(19,27*root.scaleUnit); horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
                Text { text: colonizationPage.selectedRequirementName!==""?"SELECTED REQUIREMENT":"LARGEST OUTSTANDING REQUIREMENT"; x: 24*root.scaleUnit; y: 108*root.scaleUnit; width: parent.width-48*root.scaleUnit; color: root.muted; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,11*root.scaleUnit); horizontalAlignment: Text.AlignHCenter }

                Column {
                    x: 24*root.scaleUnit; y: 151*root.scaleUnit; width: parent.width-48*root.scaleUnit; spacing: 10*root.scaleUnit
                    Repeater {
                        model: [
                            ["REMAINING",root.fmtNumber(colonizationPage.activeRemaining())+" T",root.amber],
                            ["ABOARD NOW",root.fmtNumber(colonizationPage.activeAboard())+" T",colonizationPage.activeAboard()>0?root.green:root.muted],
                            ["NEXT LOAD TARGET",root.fmtNumber(colonizationPage.activeLoadTarget())+" T",root.green],
                            ["BUY TARGET",root.fmtNumber(colonizationPage.activePurchaseTarget())+" T",colonizationPage.activePurchaseTarget()>0?root.green:root.muted],
                            ["THIS COMMODITY",bridge.cargoCapacity>0?(Math.ceil(colonizationPage.activeRemaining()/Math.max(1,bridge.cargoCapacity))+" LOAD(S)"):"CAPACITY UNKNOWN",root.whiteText],
                            ["ENTIRE PROJECT",bridge.cargoCapacity>0?("ABOUT "+bridge.colonizationProjectLoads+" LOAD"+(bridge.colonizationProjectLoads===1?"":"S")):"CAPACITY UNKNOWN",root.whiteText]
                        ]
                        Item {
                            width: parent.width; height: 38*root.scaleUnit
                            Text { text: modelData[0]; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; color: root.muted; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,12*root.scaleUnit) }
                            Text { text: modelData[1]; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: parent.width*.58; color: modelData[2]; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(11,14*root.scaleUnit); horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
                        }
                    }
                }

                Rectangle { x: 24*root.scaleUnit; y: parent.height-194*root.scaleUnit; width: parent.width-48*root.scaleUnit; height: 1; color: "#294331" }
                Text { text: "TRADE HANDOFF"; x: 24*root.scaleUnit; y: parent.height-178*root.scaleUnit; color: root.muted; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,13*root.scaleUnit) }
                Text { text: "USES TRADE ROUTE FINDER TO LOCATE SUPPLY."; x: 24*root.scaleUnit; y: parent.height-153*root.scaleUnit; width: parent.width-48*root.scaleUnit; height: 42*root.scaleUnit; color: root.whiteText; font.family: "Consolas"; font.pixelSize: Math.max(10,12*root.scaleUnit); wrapMode: Text.WordWrap }
                Item { x:24*root.scaleUnit; y:parent.height-105*root.scaleUnit; width:parent.width-48*root.scaleUnit; height:80*root.scaleUnit
                MechanicalButton {
                    anchors.fill:parent
                    text: "FIND SUPPLY"
                    subtext: colonizationPage.activePurchaseTarget()>0 ? ("SEND "+colonizationPage.activeCommodity()+" // BUY "+root.fmtNumber(colonizationPage.activePurchaseTarget())+" T VIA TRADE") : (colonizationPage.activeAboard()>0?"CURRENT ABOARD CARGO COVERS THIS NEXT LOAD TARGET":"NO OUTSTANDING MATERIAL SELECTED")
                    accent: colonizationPage.activePurchaseTarget()>0 ? root.green : root.muted
                    labelScale: .92; subtextMinSize: Math.max(10,12*root.scaleUnit)
                    onClicked: colonizationPage.findSelectedSupply()
                }
                Rectangle { anchors.fill:parent; anchors.margins:-4*root.scaleUnit; visible:colonizationPage.selectedRequirementName!=="" && colonizationPage.activePurchaseTarget()>0; color:"transparent"; border.color:root.amber; border.width:Math.max(2,3*root.scaleUnit); SequentialAnimation on opacity{running:parent.visible;loops:Animation.Infinite;NumberAnimation{to:.28;duration:420}
                                NumberAnimation{to:1;duration:420}} }
                }
            }
        }

        Row {
            id: colonyBottom
            x: 0; y: colonyTop.height + root.gap
            width: parent.width; height: parent.height-y; spacing: root.gap

            MetalPanel {
                id: colonyNavPanel
                width: colonyBottom.width * .34; height: colonyBottom.height; panelColor: root.screen
                SectionTitle { text: "NAVIGATION + FLIGHT OPS"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }
                Grid {
                    x: 20*root.scaleUnit; y: 64*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: parent.height-84*root.scaleUnit
                    columns: 3; rows: 2; columnSpacing: 9*root.scaleUnit; rowSpacing: 9*root.scaleUnit
                    MechanicalButton { enabled:bridge.eliteControlsReady && bridge.colonizationHasProject; opacity:enabled?1:.45; width: (parent.width-parent.columnSpacing*2)/3; height: (parent.height-parent.rowSpacing)/2; text: "PLOT SITE"; subtext:!bridge.eliteControlsReady?"ELITE BINDS REQUIRED":bridge.colonizationSystem; accent: bridge.colonizationHasProject?root.green:root.muted; labelScale: .70; subtextMinSize: Math.max(10,12*root.scaleUnit); onClicked: if(bridge.colonizationHasProject) bridge.plotRoute(bridge.colonizationSystem) }
                    MechanicalButton { enabled:bridge.eliteControlsReady; opacity:enabled?1:.45; width: (parent.width-parent.columnSpacing*2)/3; height: (parent.height-parent.rowSpacing)/2; text: "DOCK"; subtext:enabled?"REQUEST DOCKING":"ELITE BINDS REQUIRED"; accent: root.green; labelScale: .82; subtextMinSize: Math.max(10,12*root.scaleUnit); onClicked: bridge.requestCommand("dock") }
                    MechanicalButton { enabled:bridge.eliteControlsReady; opacity:enabled?1:.45; width: (parent.width-parent.columnSpacing*2)/3; height: (parent.height-parent.rowSpacing)/2; text: "LAUNCH"; subtext:enabled?"LEAVE STATION":"ELITE BINDS REQUIRED"; accent: root.amber; labelScale: .82; subtextMinSize: Math.max(10,12*root.scaleUnit); onClicked: bridge.requestCommand("launch") }
                    MechanicalButton { enabled:bridge.eliteControlsReady && !!bridge.navHomeSystem; opacity:enabled?1:.45; width: (parent.width-parent.columnSpacing*2)/3; height: (parent.height-parent.rowSpacing)/2; text: "HOME"; subtext:!bridge.eliteControlsReady?"ELITE BINDS REQUIRED":bridge.navHomeSystem; accent: root.green; labelScale: .82; subtextMinSize: Math.max(10,12*root.scaleUnit); onClicked: bridge.plotMemory("home") }
                    MechanicalButton { enabled:bridge.eliteControlsReady && !!bridge.navBookmark1System; opacity:enabled?1:.45; width: (parent.width-parent.columnSpacing*2)/3; height: (parent.height-parent.rowSpacing)/2; text: "BOOKMARK 1"; subtext:!bridge.eliteControlsReady?"ELITE BINDS REQUIRED":(bridge.navBookmark1System||"UNSET"); accent: bridge.navBookmark1System?root.green:root.muted; labelScale: .66; subtextMinSize: Math.max(10,12*root.scaleUnit); onClicked: if(bridge.navBookmark1System) bridge.plotMemory("bookmark1") }
                    MechanicalButton { enabled:bridge.eliteControlsReady && !!bridge.navBookmark2System; opacity:enabled?1:.45; width: (parent.width-parent.columnSpacing*2)/3; height: (parent.height-parent.rowSpacing)/2; text: "BOOKMARK 2"; subtext:!bridge.eliteControlsReady?"ELITE BINDS REQUIRED":(bridge.navBookmark2System||"UNSET"); accent: bridge.navBookmark2System?root.green:root.muted; labelScale: .66; subtextMinSize: Math.max(10,12*root.scaleUnit); onClicked: if(bridge.navBookmark2System) bridge.plotMemory("bookmark2") }
                }
            }

            MetalPanel {
                id: colonyLogPanel
                width: colonyBottom.width * .42; height: colonyBottom.height; panelColor: root.screen
                SectionTitle { text: "DELIVERY / PROJECT LOG"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }
                Text { text: "CONFIRMED CONTRIBUTIONS ARE YOUR JOURNAL EVENTS; SITE PROVIDED TOTALS MAY INCLUDE OTHER COMMANDERS."; x: 24*root.scaleUnit; y: 51*root.scaleUnit; width: parent.width-48*root.scaleUnit; color: root.muted; font.family: "Consolas"; font.pixelSize: Math.max(10,11*root.scaleUnit); elide: Text.ElideRight }
                ListView {
                    id: colonyLogList
                    x: 24*root.scaleUnit; y: 77*root.scaleUnit; width: parent.width-48*root.scaleUnit; height: parent.height-98*root.scaleUnit
                    clip: true; spacing: 4*root.scaleUnit; model: bridge.colonizationLogRows
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: colonyLogList.width-(colonyLogList.ScrollBar.vertical.visible?14*root.scaleUnit:0); height: 46*root.scaleUnit
                        color: index%2===0?"#080a08":"#070907"; border.color: "#202a23"; border.width: 1
                        Rectangle { width: 6*root.scaleUnit; height: width; radius: width/2; x: 11*root.scaleUnit; anchors.verticalCenter: parent.verticalCenter; color: String(modelData.kind)==="DELIVERY"?root.green:(String(modelData.kind)==="CLAIM"?root.amber:root.muted) }
                        Text { text: String(modelData.kind||"PROJECT"); x: 27*root.scaleUnit; width: 82*root.scaleUnit; anchors.verticalCenter: parent.verticalCenter; color: String(modelData.kind)==="DELIVERY"?root.green:(String(modelData.kind)==="CLAIM"?root.amber:root.muted); font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,11*root.scaleUnit) }
                        Text { text: String(modelData.text||"-"); x: 112*root.scaleUnit; width: parent.width-x-10*root.scaleUnit; anchors.verticalCenter: parent.verticalCenter; color: root.whiteText; font.family: "Consolas"; font.pixelSize: Math.max(10,12*root.scaleUnit); elide: Text.ElideRight }
                    }
                }
                Text { anchors.centerIn: colonyLogList; visible: colonyLogList.count===0; text: "NO CONFIRMED COLONIZATION EVENTS IN THIS JOURNAL YET"; color: root.muted; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(11,14*root.scaleUnit) }
            }

            MetalPanel {
                width: colonyBottom.width - colonyNavPanel.width - colonyLogPanel.width - root.gap*2; height: colonyBottom.height; panelColor: root.screen
                SectionTitle { text: "PROJECT STATUS"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }
                Column {
                    x: 20*root.scaleUnit; y: 62*root.scaleUnit; width: parent.width-40*root.scaleUnit; spacing: 8*root.scaleUnit
                    StatusLamp { width: parent.width; height: 35*root.scaleUnit; label: "PROJECT"; value: bridge.colonizationStatus; stateColor: bridge.colonizationStatus==="FAILED"?root.red:(bridge.colonizationHasProject?root.green:root.amber); phase: bridge.pulse; pulse: bridge.colonizationHasProject }
                    StatusLamp { width: parent.width; height: 35*root.scaleUnit; label: "OPEN TYPES"; value: String(bridge.colonizationIncompleteCount); stateColor: bridge.colonizationIncompleteCount>0?root.amber:root.green; phase: bridge.pulse }
                    StatusLamp { width: parent.width; height: 35*root.scaleUnit; label: "SAVED PROJECTS"; value: String(bridge.colonizationProjectRows.length); stateColor: bridge.colonizationProjectRows.length>0?root.green:root.amber; phase: bridge.pulse }
                    StatusLamp { width: parent.width; height: 35*root.scaleUnit; label: "CLAIM / BEACON"; value: bridge.colonizationClaimStatus; stateColor: bridge.colonizationClaimStatus!=="-"?root.amber:root.muted; phase: bridge.pulse }
                }
                Rectangle { x: 20*root.scaleUnit; y: parent.height-104*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 1; color: "#294331" }
                Text { text: "DATA SOURCE"; x: 20*root.scaleUnit; y: parent.height-89*root.scaleUnit; color: root.muted; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,11*root.scaleUnit) }
                Text { text: bridge.colonizationDataSource; x: 20*root.scaleUnit; y: parent.height-68*root.scaleUnit; width: parent.width-40*root.scaleUnit; color: root.green; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,12*root.scaleUnit); elide: Text.ElideRight }
                Text { text: "LAST EVENT // "+bridge.colonizationLastEvent; x: 20*root.scaleUnit; y: parent.height-43*root.scaleUnit; width: parent.width-40*root.scaleUnit; color: root.muted; font.family: "Consolas"; font.pixelSize: Math.max(10,11*root.scaleUnit); elide: Text.ElideRight }
            }
        }
    }


    // COMMANDER MODULE: pilot record, current vessel, cargo, and session/history records.
    Item {
        id: commanderPage
        visible: root.currentPage === 5
        x: identity.x
        y: liveSectionTabs.y + liveSectionTabs.height + root.gap
        width: identity.width
        height: root.height - y - root.m

        Row {
            id: commanderTop
            width: parent.width
            height: parent.height * .58
            spacing: root.gap

            MetalPanel {
                width: commanderTop.width * .34
                height: commanderTop.height
                panelColor: root.screen
                SectionTitle { text: "COMMANDER DOSSIER"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }

                Rectangle {
                    x: 28*root.scaleUnit; y: 70*root.scaleUnit; width: parent.width-56*root.scaleUnit; height: 92*root.scaleUnit
                    color: "#061008"; border.color: "#285338"; border.width: 1
                    Text { text: "COMMANDER"; x: 16*root.scaleUnit; y: 12*root.scaleUnit; color: "#718178"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(13,17*root.scaleUnit) }
                    Text { text: bridge.commander.toUpperCase(); x: 16*root.scaleUnit; y: 38*root.scaleUnit; width: parent.width-62*root.scaleUnit; color: root.green; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(25,38*root.scaleUnit); elide: Text.ElideRight }
                    Rectangle { width: 10*root.scaleUnit; height: width; radius: width/2; color: root.green; anchors.right: parent.right; anchors.rightMargin: 18*root.scaleUnit; anchors.verticalCenter: parent.verticalCenter; opacity: .70 + .20*Math.sin(bridge.pulse*6.28318) }
                }

                Column {
                    visible: bridge.bridgeMode !== "CORE"
                    x: 28*root.scaleUnit; y: 178*root.scaleUnit; width: parent.width-56*root.scaleUnit; spacing: 8*root.scaleUnit
                    Repeater {
                        model: bridge.commanderDossierRows
                        Item {
                            width: parent.width; height: 31*root.scaleUnit
                            Text { text: modelData.label; color: "#87958b"; font.family: "Consolas"; font.pixelSize: Math.max(12,16*root.scaleUnit); anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: String(modelData.value).toUpperCase(); color: bridge.levelColor(modelData.level); font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(13,17*root.scaleUnit); anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: parent.width*.58; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
                        }
                    }
                }

                Text {
                    text: "LIVE JOURNAL DOSSIER // NO ESTIMATED COMMANDER VALUES"
                    x: 28*root.scaleUnit; y: parent.height-44*root.scaleUnit; width: parent.width-56*root.scaleUnit
                    color: "#68786e"; font.family: "Consolas"; font.pixelSize: Math.max(10,13*root.scaleUnit); elide: Text.ElideRight
                }
            }

            MetalPanel {
                width: commanderTop.width * .39
                height: commanderTop.height
                panelColor: root.screen
                SectionTitle { text: "CURRENT VESSEL"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }

                Rectangle {
                    x: 28*root.scaleUnit; y: 70*root.scaleUnit; width: parent.width*.55; height: parent.height-118*root.scaleUnit
                    color: "#041008"; border.color: "#1f6136"; border.width: 1
                    Text {
                        text: (bridge.shipName && bridge.shipName !== "-") ? bridge.shipName.toUpperCase() : String(bridge.shipModel).replace(/_/g," ").toUpperCase()
                        x: 14*root.scaleUnit; y: 10*root.scaleUnit; width: parent.width-28*root.scaleUnit
                        color: root.green; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(15,20*root.scaleUnit); elide: Text.ElideRight
                    }
                    Text {
                        text: String(bridge.shipModel).replace(/_/g," ").toUpperCase()
                        x: 14*root.scaleUnit; y: 34*root.scaleUnit; width: parent.width-28*root.scaleUnit
                        color: "#7c9182"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(10,13*root.scaleUnit); elide: Text.ElideRight
                    }
                    Image {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                        anchors.leftMargin: 10*root.scaleUnit; anchors.rightMargin: 10*root.scaleUnit; anchors.topMargin: 56*root.scaleUnit; anchors.bottomMargin: 10*root.scaleUnit
                        source: root.shipArtSource(bridge.shipModel)
                        fillMode: Image.PreserveAspectFit
                        smooth: true; mipmap: true
                        opacity: .90
                        scale: 1.10
                    }
                    ScanGrid { anchors.fill: parent; anchors.margins: 10*root.scaleUnit; opacity: .18; step: 28; majorEvery: 5 }
                }

                Column {
                    x: parent.width*.60; y: 84*root.scaleUnit; width: parent.width*.35; spacing: 14*root.scaleUnit
                    Repeater {
                        model: [
                            ["HULL",bridge.hullPercent>=0 ? bridge.hullPercent+"%" : "UNKNOWN",bridge.hullPercent>=0?(bridge.hullPercent<40?root.red:root.green):root.muted],
                            ["SHIELDS",bridge.shieldState,bridge.shieldState==="UNKNOWN"?root.muted:(bridge.shieldState==="DOWN"?root.red:root.green)],
                            ["FUEL",bridge.fuelPercent>=0 ? bridge.fuelPercent+"%" : "UNKNOWN",bridge.fuelPercent>=0?(bridge.fuelPercent<20?root.amber:root.green):root.muted],
                            ["CARGO",bridge.cargoText,bridge.cargoText==="UNKNOWN"?root.muted:root.green],
                            ["FSD",bridge.fsdState,bridge.fsdState==="UNKNOWN"?root.muted:(bridge.fsdState==="MASS LOCKED"?root.red:root.green)],
                            ["LANDING GEAR",bridge.gearState,bridge.gearState==="UNKNOWN"?root.muted:root.green],
                            ["HARDPOINTS",bridge.hardpointsState,bridge.hardpointsState==="UNKNOWN"?root.muted:(bridge.hardpointsState==="DEPLOYED"?root.amber:root.green)]
                        ]
                        Item {
                            width: parent.width; height: 34*root.scaleUnit
                            Text { text: modelData[0]; color: "#87958b"; font.family: "Consolas"; font.pixelSize: Math.max(13,17*root.scaleUnit); anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: String(modelData[1]).toUpperCase(); color: modelData[2]; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(14,18*root.scaleUnit); anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: parent.width*.54; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
                        }
                    }
                }
            }

            Column {
                width: commanderTop.width - commanderTop.children[0].width - commanderTop.children[1].width - root.gap*2
                height: commanderTop.height
                spacing: root.gap

                MetalPanel {
                    width: parent.width; height: (parent.height-root.gap)*.52
                    panelColor: root.screen
                    SectionTitle { text: "RECORD STATUS"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }
                    Column {
                        x: 28*root.scaleUnit; y: 66*root.scaleUnit; width: parent.width-56*root.scaleUnit; spacing: 7*root.scaleUnit
                        Repeater {
                            model: bridge.commanderRecordRows
                            StatusLamp { width: parent.width; height: 35*root.scaleUnit; label: modelData.label; value: modelData.value; stateColor: bridge.levelColor(modelData.level); phase: bridge.pulse; pulse: index<2 && modelData.value==="LIVE"; fontScale: 1.10 }
                        }
                    }
                }

                MetalPanel {
                    width: parent.width; height: parent.height-parent.children[0].height-root.gap
                    panelColor: root.screen
                    SectionTitle { text: "CAREER / HISTORY"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }
                    Column {
                        x: 28*root.scaleUnit; y: 64*root.scaleUnit; width: parent.width-56*root.scaleUnit; spacing: 6*root.scaleUnit
                        Repeater {
                            model: bridge.commanderCareerRows
                            Item {
                                width: parent.width; height: 27*root.scaleUnit
                                Text { text: modelData.label; color: "#87958b"; font.family: "Consolas"; font.pixelSize: Math.max(11,14*root.scaleUnit); anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: String(modelData.value).toUpperCase(); color: bridge.levelColor(modelData.level); font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(12,16*root.scaleUnit); anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: parent.width*.53; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
                            }
                        }
                    }
                    Rectangle { x: 28*root.scaleUnit; y: parent.height-52*root.scaleUnit; width: parent.width-56*root.scaleUnit; height: 32*root.scaleUnit; color: "#080a08"; border.color: bridge.commanderHistoryAvailable?"#285338":"#27362b"; border.width: 1
                        Text { text: bridge.commanderHistoryNote; anchors.centerIn: parent; width: parent.width-16*root.scaleUnit; horizontalAlignment: Text.AlignHCenter; color: bridge.commanderHistoryAvailable?root.green:"#68786e"; font.family: "Consolas"; font.pixelSize: Math.max(10,11*root.scaleUnit); elide: Text.ElideRight }
                    }
                }
            }
        }

        Row {
            id: commanderBottom
            x: 0; y: commanderTop.height + root.gap
            width: parent.width; height: parent.height-y; spacing: root.gap

            MetalPanel {
                width: commanderBottom.width*.34; height: commanderBottom.height; panelColor: root.screen
                SectionTitle { text: "CARGO / STORAGE"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }

                Text { text: "CARGO HOLD"; x: 28*root.scaleUnit; y: 70*root.scaleUnit; color: "#87958b"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(14,18*root.scaleUnit) }
                Text { text: bridge.cargoUsed + " / " + bridge.cargoCapacity + " T"; anchors.right: parent.right; anchors.rightMargin: 28*root.scaleUnit; y: 70*root.scaleUnit; color: root.green; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(17,24*root.scaleUnit) }
                SegmentBar { x: 28*root.scaleUnit; y: 106*root.scaleUnit; width: parent.width-56*root.scaleUnit; height: 27*root.scaleUnit; segments: 10; value: bridge.cargoCapacity>0 ? Math.min(10,Math.ceil(bridge.cargoUsed/bridge.cargoCapacity*10)) : 0; onColor: root.green; offColor: "#102719" }

                Text { text: "MANIFEST // "+bridge.commanderCargoTypeCount+" TYPE(S) // "+bridge.commanderCargoSource.toUpperCase(); x: 28*root.scaleUnit; y: 148*root.scaleUnit; width: parent.width-56*root.scaleUnit; color: "#65776b"; font.family: "Consolas"; font.pixelSize: Math.max(10,13*root.scaleUnit); elide: Text.ElideRight }

                Column {
                    x: 28*root.scaleUnit; y: 178*root.scaleUnit; width: parent.width-56*root.scaleUnit; spacing: 8*root.scaleUnit
                    Repeater {
                        model: bridge.commanderCargoRows.length ? bridge.commanderCargoRows : [{"label":"COMMODITIES","value":"NONE ABOARD","level":"info"}]
                        Rectangle {
                            width: parent.width; height: 34*root.scaleUnit; color: "#080a08"; border.color: "#1d3024"; border.width: 1
                            Text { text: modelData.label; x: 10*root.scaleUnit; anchors.verticalCenter: parent.verticalCenter; width: parent.width*.58; color: root.whiteText; font.family: "Consolas"; font.pixelSize: Math.max(11,14*root.scaleUnit); elide: Text.ElideRight }
                            Text { text: modelData.value; anchors.right: parent.right; anchors.rightMargin: 10*root.scaleUnit; anchors.verticalCenter: parent.verticalCenter; width: parent.width*.39; horizontalAlignment: Text.AlignRight; color: bridge.levelColor(modelData.level); font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(11,14*root.scaleUnit); elide: Text.ElideRight }
                        }
                    }
                }

                Column {
                    x: 28*root.scaleUnit; y: parent.height-112*root.scaleUnit; width: parent.width-56*root.scaleUnit; spacing: 8*root.scaleUnit
                    Repeater {
                        model: [
                            ["COLLECTOR LIMPETS",bridge.commanderLimpetReserve+" IN HOLD",bridge.commanderLimpetReserve>0?root.green:root.whiteText],
                            ["ILLEGAL / STOLEN",bridge.commanderStolenCargo>0?bridge.commanderStolenCargo+" T ABOARD":"NONE DETECTED",bridge.commanderStolenCargo>0?root.red:root.green]
                        ]
                        Item {
                            width: parent.width; height: 28*root.scaleUnit
                            Text { text: modelData[0]; color: "#87958b"; font.family: "Consolas"; font.pixelSize: Math.max(11,14*root.scaleUnit); anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: modelData[1]; color: modelData[2]; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(11,14*root.scaleUnit); anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: parent.width*.52; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
                        }
                    }
                }
            }

            MetalPanel {
                width: commanderBottom.width*.34; height: commanderBottom.height; panelColor: root.screen
                SectionTitle { text: "SESSION RECORD"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }

                Column {
                    x: 28*root.scaleUnit; y: 68*root.scaleUnit; width: parent.width-56*root.scaleUnit; spacing: 10*root.scaleUnit
                    Repeater {
                        model: bridge.commanderSessionRows
                        Rectangle {
                            width: parent.width; height: 36*root.scaleUnit
                            color: index===0 ? "#100e08" : "#080a08"; border.color: index===0 ? "#5b4525" : "#222b24"; border.width: 1
                            Text { text: modelData.label; x: 12*root.scaleUnit; color: "#87958b"; font.family: "Consolas"; font.pixelSize: Math.max(12,15*root.scaleUnit); anchors.verticalCenter: parent.verticalCenter }
                            Text { text: modelData.value; anchors.right: parent.right; anchors.rightMargin: 12*root.scaleUnit; color: bridge.levelColor(modelData.level); font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(12,16*root.scaleUnit); anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                }
                Text { text: "SESSION COUNTS BEGIN WHEN THIS BRIDGE INSTANCE STARTS"; x: 28*root.scaleUnit; y: parent.height-38*root.scaleUnit; width: parent.width-56*root.scaleUnit; color: "#68786e"; font.family: "Consolas"; font.pixelSize: Math.max(10,11*root.scaleUnit); elide: Text.ElideRight }
            }

            MetalPanel {
                width: commanderBottom.width - commanderBottom.children[0].width - commanderBottom.children[1].width - root.gap*2
                height: commanderBottom.height; panelColor: root.screen
                SectionTitle { text: "RECORD ACTIONS"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }
                Grid {
                    x: 20*root.scaleUnit; y: 66*root.scaleUnit
                    width: parent.width-40*root.scaleUnit; height: parent.height-88*root.scaleUnit
                    columns: 2; rows: 2; columnSpacing: 10*root.scaleUnit; rowSpacing: 10*root.scaleUnit
                    MechanicalButton { width: (parent.width-parent.columnSpacing)/2; height: (parent.height-parent.rowSpacing)/2; text: "SAVE RECORD"; subtext: "JSON + SUPPORT ZIP"; accent: root.green; labelScale: .74; onClicked: bridge.requestCommand("save_data") }
                    MechanicalButton { width: (parent.width-parent.columnSpacing)/2; height: (parent.height-parent.rowSpacing)/2; text: "JOURNAL"; subtext: "OPEN FOLDER"; accent: root.green; labelScale: .86; onClicked: bridge.requestCommand("journal") }
                    MechanicalButton { width: (parent.width-parent.columnSpacing)/2; height: (parent.height-parent.rowSpacing)/2; text: "DIAGNOSTIC"; subtext: "COPY REPORT"; accent: root.amber; labelScale: .70; onClicked: bridge.requestCommand("diagnostic") }
                    MechanicalButton { width: (parent.width-parent.columnSpacing)/2; height: (parent.height-parent.rowSpacing)/2; text: "REFRESH"; subtext: "HISTORY + RECORD"; accent: root.green; labelScale: .82; onClicked: bridge.requestCommand("cmdr_refresh") }
                }
            }
        }
    }


    // Configuration views are nested under SETUP. The old page IDs remain
    // intact so existing automation and AI routing do not need to change.
    Item {
        id: setupSectionTabs
        visible: root.currentPage === 6 || root.currentPage === 7 || root.currentPage === 8 || root.currentPage === 9 || root.currentPage === 10
        x: identity.x; y: identity.y+identity.height+root.gap
        width: identity.width; height: 76*root.scaleUnit
        Row {
            anchors.fill:parent; spacing:10*root.scaleUnit
            TradeModeButton {
                width:(parent.width-parent.spacing*4)/5; height:parent.height
                text:"SYSTEM"; subtext:"HEALTH + GENERAL"
                active:root.currentPage===8; accent:root.green; scaleUnit:root.scaleUnit
                onClicked:{root.currentPage=8;setupScroll.contentY=0;bridge.playUiCue("nav")}
            }
            TradeModeButton {
                width:(parent.width-parent.spacing*4)/5; height:parent.height
                text:"CONTROLS"; subtext:"PTT + SHORTCUTS + BINDS"
                active:root.currentPage===10; accent:root.green; scaleUnit:root.scaleUnit
                onClicked:{root.currentPage=10;controlsScroll.contentY=0;bridge.playUiCue("nav")}
            }
            TradeModeButton {
                width:(parent.width-parent.spacing*4)/5; height:parent.height
                text:"AI & VOICE"; subtext:"ASSISTANCE + SPEECH"
                active:root.currentPage===6; accent:root.green; scaleUnit:root.scaleUnit
                onClicked:{root.currentPage=6;voiceTuningScroll.contentY=0;bridge.playUiCue("nav")}
            }
            TradeModeButton {
                width:(parent.width-parent.spacing*4)/5; height:parent.height
                text:"AUDIO"; subtext:"DEVICES + LEVELS + SFX"
                active:root.currentPage===7; accent:root.green; scaleUnit:root.scaleUnit
                onClicked:{root.currentPage=7;sfxListScroll.contentY=0;bridge.playUiCue("nav")}
            }
            TradeModeButton {
                width:(parent.width-parent.spacing*4)/5; height:parent.height
                text:"DISPLAY"; subtext:"MONITOR + WINDOW"
                active:root.currentPage===9; accent:root.green; scaleUnit:root.scaleUnit
                onClicked:{root.currentPage=9;bridge.playUiCue("nav")}
            }
        }
    }

    // AI & VOICE MODULE: nested Setup view for copilot, voice pipeline and permissions.
    Item {
        id: aiVoicePage
        visible: root.currentPage === 6
        x: identity.x
        y: setupSectionTabs.y + setupSectionTabs.height + root.gap
        width: identity.width
        height: root.height - y - root.m

        Row {
            id: aiTop
            width: parent.width
            height: parent.height * .57
            spacing: root.gap

            MetalPanel {
                visible: bridge.bridgeMode !== "CORE"
                width: visible ? aiTop.width * .35 : 0
                height: aiTop.height
                panelColor: root.screen
                SectionTitle { text: "AI CO-PILOT"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }

                Rectangle {
                    visible: bridge.bridgeMode !== "CORE"
                    x: 28*root.scaleUnit; y: 68*root.scaleUnit; width: parent.width-56*root.scaleUnit; height: 92*root.scaleUnit
                    color: "#061008"; border.color: bridge.aiApiConfigured ? "#285338" : root.red; border.width: 1
                    Text { text: "LIVE MODEL"; x: 16*root.scaleUnit; y: 12*root.scaleUnit; color: "#718178"; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(13,17*root.scaleUnit) }
                    Text { text: bridge.aiModel.toUpperCase(); x: 16*root.scaleUnit; y: 39*root.scaleUnit; width: parent.width-54*root.scaleUnit; color: bridge.aiApiConfigured ? root.green : root.red; font.family: "Consolas"; font.bold: true; font.pixelSize: Math.max(22,31*root.scaleUnit); elide: Text.ElideRight }
                    Rectangle { width: 11*root.scaleUnit; height: width; radius: width/2; color: bridge.aiApiConfigured ? root.green : root.red; anchors.right: parent.right; anchors.rightMargin: 18*root.scaleUnit; anchors.verticalCenter: parent.verticalCenter; opacity: .72+.20*Math.sin(bridge.pulse*6.28318) }
                }

                Column {
                    visible: bridge.bridgeMode !== "CORE"
                    x: 28*root.scaleUnit; y: 178*root.scaleUnit; width: parent.width-56*root.scaleUnit; spacing: 8*root.scaleUnit
                    StatusLamp { width: parent.width; height: 37*root.scaleUnit; label: "CO-PILOT"; value: bridge.aiCopilotStatus.toUpperCase(); stateColor: bridge.lunaStatus==="NO KEY"?root.red:(bridge.lunaStatus==="THINKING"?root.amber:root.green); pulse: bridge.lunaStatus==="THINKING"; phase: bridge.pulse; fontScale:1.12 }
                    StatusLamp { width: parent.width; height: 37*root.scaleUnit; label: "API PROFILE"; value: bridge.aiApiConfigured?"CONFIGURED":"OPTIONAL"; stateColor: bridge.aiApiConfigured?root.green:root.amber; phase: bridge.pulse; fontScale:1.12 }
                    StatusLamp { width: parent.width; height: 37*root.scaleUnit; label: "ACTION MODE"; value: bridge.aiToolMode.toUpperCase(); stateColor: bridge.aiToolMode==="Suggest Only"?root.whiteText:(bridge.aiToolMode==="Ask Before Acting"?root.amber:root.green); phase: bridge.pulse; fontScale:1.12 }
                    StatusLamp { width: parent.width; height: 37*root.scaleUnit; label: "SAFETY WATCH"; value: bridge.aiSafetyLevel; stateColor: (bridge.aiSafetyLevel==="DANGER"||bridge.aiSafetyLevel==="CRITICAL")?root.red:(bridge.aiSafetyLevel==="WARNING"?root.amber:root.green); phase: bridge.pulse; fontScale:1.12 }
                    StatusLamp { width: parent.width; height: 37*root.scaleUnit; label: "PENDING ACTION"; value: bridge.aiPendingAction; stateColor: bridge.aiPendingActionAvailable?root.amber:root.green; pulse: bridge.aiPendingActionAvailable; phase: bridge.pulse; fontScale:1.08 }
                }

                Rectangle {
                    visible: bridge.bridgeMode === "CORE"
                    x:28*root.scaleUnit; y:68*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:parent.height-94*root.scaleUnit
                    color:"#050b0d"; border.color:"#315864"; border.width:2
                    VoiceWave { x:18*root.scaleUnit; y:20*root.scaleUnit; width:parent.width-36*root.scaleUnit; height:86*root.scaleUnit; color:"#55d7ff"; activeColor:root.green; speaking:true; listening:false; phase:bridge.pulse }
                    Text { text:"CORE BRIDGE ACTIVE"; x:18*root.scaleUnit; y:118*root.scaleUnit; width:parent.width-36*root.scaleUnit; color:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(15,20*root.scaleUnit); horizontalAlignment:Text.AlignHCenter }
                    Text { text:"Upgrade when you want conversational voice commands, AI questions and answers, contextual guidance, and AI-assisted Bridge control. Your existing Core setup stays intact until the upgrade completes."; x:18*root.scaleUnit; y:158*root.scaleUnit; width:parent.width-36*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(10,13*root.scaleUnit); wrapMode:Text.WordWrap; horizontalAlignment:Text.AlignHCenter }
                    Text { text:"REQUIRES A THIRD-PARTY OPENAI API KEY"; x:18*root.scaleUnit; y:258*root.scaleUnit; width:parent.width-36*root.scaleUnit; color:root.amber; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,11*root.scaleUnit); horizontalAlignment:Text.AlignHCenter }
                    MechanicalButton { x:18*root.scaleUnit; y:parent.height-112*root.scaleUnit; width:parent.width-36*root.scaleUnit; height:88*root.scaleUnit; text:"UPGRADE TO AI CO-PILOT"; subtext:"START THE AI UPGRADE WIZARD"; accent:root.green; labelScale:.66; onClicked:root.openCopilotUpgradeWizard() }
                }

                Rectangle {
                    visible: bridge.bridgeMode !== "CORE"
                    x: 28*root.scaleUnit; y: parent.height-112*root.scaleUnit; width: parent.width-56*root.scaleUnit; height: 86*root.scaleUnit
                    color: "#080b08"; border.color: "#2c3a2f"; border.width: 1
                    Text { text:"LATEST CO-PILOT"; x:12*root.scaleUnit; y:8*root.scaleUnit; color:root.amber; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,13*root.scaleUnit) }
                    Text { text:bridge.aiCopilotResponse; x:12*root.scaleUnit; y:28*root.scaleUnit; width:parent.width-24*root.scaleUnit; height:parent.height-34*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(10,13*root.scaleUnit); wrapMode:Text.WordWrap; maximumLineCount:3; elide:Text.ElideRight }
                }
            }

            MetalPanel {
                width: bridge.bridgeMode === "CORE" ? aiTop.width * .48 : aiTop.width * .37
                height: aiTop.height
                panelColor: root.screen
                SectionTitle { text: "VOICE STATUS"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }

                VoiceWave {
                    x: 30*root.scaleUnit; y: 68*root.scaleUnit; width: 190*root.scaleUnit; height: 92*root.scaleUnit
                    color: root.green; activeColor: root.amber
                    speaking: bridge.voiceMode === "SPEAKING"
                    listening: bridge.voiceMode === "LISTENING"
                    phase: bridge.pulse
                }
                Text { text: bridge.voiceMode==="SPEAKING"?"SPEAKING":(bridge.voiceMode==="LISTENING"?"LISTENING":(bridge.bridgeMode==="CORE"?"BRIDGE VOICE READY":"VOICE READY")); x:238*root.scaleUnit; y:82*root.scaleUnit; width:parent.width-268*root.scaleUnit; color:bridge.voiceMode==="SPEAKING"?root.amber:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(18,24*root.scaleUnit); elide:Text.ElideRight }
                Text { text: bridge.bridgeMode==="CORE"?"Core Bridge uses this voice for alerts, confirmations and automation feedback.":bridge.voiceInputStatus; x:238*root.scaleUnit; y:116*root.scaleUnit; width:parent.width-268*root.scaleUnit; height:48*root.scaleUnit; color:"#96a399"; font.family:"Consolas"; font.pixelSize:Math.max(11,14*root.scaleUnit); wrapMode:Text.WordWrap; maximumLineCount:2; elide:Text.ElideRight }

                Column {
                    x: 28*root.scaleUnit; y: 176*root.scaleUnit; width: parent.width-56*root.scaleUnit; spacing: 8*root.scaleUnit
                    Repeater {
                        model: bridge.bridgeMode === "CORE" ? [
                            ["MODE","CORE BRIDGE VOICE",root.green],
                            ["AUDIO OUTPUT",bridge.voiceOutputDevice,root.whiteText],
                            ["VOICE ENGINE",bridge.voiceEngineMode+" // "+bridge.voiceName,root.green]
                        ] : [
                            ["INPUT MODE",bridge.voiceInputMode,root.green],
                            ["PTT MAPPING",bridge.pttStatus==="NOT MAPPED"?"FALLBACK ONLY":bridge.voicePttMapping,bridge.pttStatus==="NOT MAPPED"?root.amber:root.green],
                            ["MICROPHONE",bridge.voiceInputDevice,root.whiteText],
                            ["AUDIO OUTPUT",bridge.voiceOutputDevice,root.whiteText],
                            ["VOICE ENGINE",bridge.voiceEngineMode+" // "+bridge.voiceName,root.green]
                        ]
                        Item {
                            width: parent.width; height: 30*root.scaleUnit
                            Text { text:modelData[0]; color:"#87958b"; font.family:"Consolas"; font.pixelSize:Math.max(12,15*root.scaleUnit); anchors.left:parent.left; anchors.verticalCenter:parent.verticalCenter }
                            Text { text:modelData[1]; color:modelData[2]; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit); anchors.right:parent.right; anchors.verticalCenter:parent.verticalCenter; width:parent.width*.62; horizontalAlignment:Text.AlignRight; elide:Text.ElideRight }
                        }
                    }
                }

                Text { visible:bridge.bridgeMode !== "CORE"; text:"MIC LEVEL"; x:28*root.scaleUnit; y:370*root.scaleUnit; color:"#87958b"; font.family:"Consolas"; font.pixelSize:Math.max(11,14*root.scaleUnit) }
                SegmentBar { visible:bridge.bridgeMode !== "CORE"; x:110*root.scaleUnit; y:370*root.scaleUnit; width:parent.width-138*root.scaleUnit; height:20*root.scaleUnit; segments:12; value:bridge.voiceMicSegments; onColor:root.green; offColor:"#112016" }
                Text { visible:bridge.bridgeMode !== "CORE"; text:"LAST HEARD // "+(bridge.voiceLastText==="-"?"NONE":bridge.voiceLastText); x:28*root.scaleUnit; y:400*root.scaleUnit; width:parent.width-56*root.scaleUnit; color:"#809087"; font.family:"Consolas"; font.pixelSize:Math.max(10,13*root.scaleUnit); elide:Text.ElideRight }

                Row {
                    x: 28*root.scaleUnit; y: parent.height-96*root.scaleUnit; width: parent.width-56*root.scaleUnit; height: 70*root.scaleUnit; spacing: 8*root.scaleUnit
                    Repeater {
                        model: bridge.bridgeMode === "CORE" ? [["VOICE TEST","HEAR BRIDGE ALERT / CONFIRMATION VOICE"]] : [["MIC CHECK","5 SEC LOCAL METER // NO PTT"],["TRANSCRIPTION TEST","5 SEC // WHAT AI HEARS // NO COMMAND"],["VOICE TEST","TTS OUTPUT"]]
                        MechanicalButton { width:bridge.bridgeMode === "CORE" ? parent.width : (parent.width-parent.spacing*2)/3; height:parent.height; text:modelData[0]; subtext:modelData[1]; accent:root.green; labelScale:bridge.bridgeMode === "CORE"?.70:.58; subtextMinSize:Math.max(8,10*root.scaleUnit); onClicked:bridge.requestCommand(bridge.bridgeMode === "CORE"?"voice_test":(index===0?"mic_test":index===1?"hearing_test":"voice_test")) }
                    }
                }
            }

            MetalPanel {
                width: bridge.bridgeMode === "CORE" ? (aiTop.width - aiTop.children[1].width - root.gap) : (aiTop.width - aiTop.children[0].width - aiTop.children[1].width - root.gap*2)
                height: aiTop.height
                panelColor: root.screen
                SectionTitle { text: bridge.bridgeMode === "CORE" ? "AI CO-PILOT UPGRADE" : "AI MISSION CONTEXT"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }
                Text { text:bridge.bridgeMode === "CORE" ? "AI CO-PILOT IS AN OPTIONAL UPGRADE TO CORE BRIDGE. IT ADDS CONVERSATIONAL VOICE CONTROL AND AI ASSISTANCE WITHOUT REMOVING YOUR BUTTONS OR AUTOMATION." : "OPTIONAL // TELL THE AI WHAT YOU ARE DOING OR WHAT KIND OF HELP YOU WANT. THIS CONTEXT IS INCLUDED WITH AI REQUESTS UNTIL YOU CHANGE OR RESET IT."; x:24*root.scaleUnit; y:58*root.scaleUnit; width:parent.width-48*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,11*root.scaleUnit); wrapMode:Text.WordWrap }
                Rectangle {
                    visible: bridge.bridgeMode !== "CORE"
                    anchors.right:parent.right; anchors.rightMargin:24*root.scaleUnit; y:18*root.scaleUnit
                    width:170*root.scaleUnit; height:30*root.scaleUnit; radius:2
                    color:resetContextMouse.containsMouse?"#102016":"#080b08"; border.color:resetContextMouse.containsMouse?root.green:"#435247"; border.width:1
                    Text { anchors.centerIn:parent; text:"↺ RESET DEFAULT"; color:resetContextMouse.containsMouse?root.green:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,10*root.scaleUnit) }
                    MouseArea {
                        id:resetContextMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
                        onClicked:{
                            // Reset is immediate in the editor instead of waiting for the
                            // next backend poll. Clearing focus also prevents TextArea
                            // focus guard from hiding the backend reset update.
                            setupAiContextInput.focus=false
                            setupPage.aiContextDraft=bridge.setupAiContextDefault
                            bridge.setSetupValue("ai_context_reset","1")
                            bridge.playUiCue("confirm")
                        }
                    }
                }
                Item {
                    visible: bridge.bridgeMode === "CORE"
                    x:24*root.scaleUnit; y:118*root.scaleUnit; width:parent.width-48*root.scaleUnit; height:parent.height-150*root.scaleUnit
                    VoiceWave { anchors.horizontalCenter:parent.horizontalCenter; y:10*root.scaleUnit; width:parent.width*.72; height:100*root.scaleUnit; color:"#55d7ff"; activeColor:root.green; speaking:true; listening:false; phase:bridge.pulse }
                    Text { text:"WHAT AI CO-PILOT ADDS"; x:0; y:126*root.scaleUnit; width:parent.width; color:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(13,17*root.scaleUnit); horizontalAlignment:Text.AlignHCenter }
                    Text { text:"• Natural Push-to-Talk voice commands\n• Conversational questions and answers\n• Context-aware guidance using live Bridge data\n• AI-assisted Bridge controls with your chosen approval rules"; x:12*root.scaleUnit; y:164*root.scaleUnit; width:parent.width-24*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(10,13*root.scaleUnit); lineHeight:1.35; wrapMode:Text.WordWrap }
                    MechanicalButton { x:12*root.scaleUnit; y:parent.height-94*root.scaleUnit; width:parent.width-24*root.scaleUnit; height:78*root.scaleUnit; text:"UPGRADE TO AI CO-PILOT"; subtext:"API KEY → BRIDGE VOICE → PTT → ENABLE"; accent:root.green; labelScale:.62; onClicked:root.openCopilotUpgradeWizard() }
                }

                Rectangle {
                    visible: bridge.bridgeMode !== "CORE"
                    x:24*root.scaleUnit; y:112*root.scaleUnit; width:parent.width-48*root.scaleUnit; height:parent.height-282*root.scaleUnit
                    color:"#061008"; border.color:setupAiContextInput.activeFocus?root.green:"#244a30"; border.width:1
                    TextArea {
                        id:setupAiContextInput; text:setupPage.aiContextDraft; anchors.fill:parent; anchors.margins:6*root.scaleUnit
                        color:root.whiteText; selectionColor:root.dimGreen; selectedTextColor:root.whiteText
                        font.family:"Consolas"; font.pixelSize:Math.max(11,14*root.scaleUnit); wrapMode:TextEdit.Wrap; selectByMouse:true
                        placeholderText:"Describe what you want the Bridge to prioritize."; placeholderTextColor:root.muted
                        background: Rectangle { color:"#061008"; border.color:"transparent" }
                        onTextChanged:{ if(activeFocus) setupPage.aiContextDraft=text.slice(0,1000) }
                    }
                }
                Text { visible: bridge.bridgeMode !== "CORE"; text:"THIRD-PARTY AI NOTICE // OpenAI controls API availability, pricing and billing. You are responsible for your API account, key, usage and spending limits. Bridge cost estimates are informational and AI responses may be inaccurate."; x:24*root.scaleUnit; y:parent.height-148*root.scaleUnit; width:parent.width-48*root.scaleUnit; color:root.amber; font.family:"Consolas"; font.pixelSize:Math.max(10,10*root.scaleUnit); wrapMode:Text.WordWrap }
                Row {
                    visible: bridge.bridgeMode !== "CORE"
                    x:24*root.scaleUnit; y:parent.height-96*root.scaleUnit; width:parent.width-48*root.scaleUnit; height:70*root.scaleUnit; spacing:10*root.scaleUnit
                    MechanicalButton { width:parent.width; height:parent.height; text:"SAVE AI CONTEXT"; subtext:"BLANK RESTORES DEFAULT"; accent:root.green; labelScale:.60; onClicked:{ if(setupPage.aiContextDraft.trim().length===0) setupPage.aiContextDraft=bridge.setupAiContextDefault; bridge.setSetupValue("ai_context",setupPage.aiContextDraft) } }
                }
            }
        }

        Row {
            id: aiBottom
            x:0; y:aiTop.height+root.gap
            width:parent.width; height:parent.height-y; spacing:root.gap

            MetalPanel {
                width:aiBottom.width*.33; height:aiBottom.height; panelColor:root.screen
                SectionTitle { text:"VOICE PROFILE / TUNING"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }
                Flickable {
                    id:voiceTuningScroll
                    x:16*root.scaleUnit; y:54*root.scaleUnit; width:parent.width-32*root.scaleUnit; height:parent.height-68*root.scaleUnit
                    clip:true; contentWidth:width; contentHeight:500*root.scaleUnit; boundsBehavior:Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    Item {
                        width:voiceTuningScroll.width-12*root.scaleUnit; height:500*root.scaleUnit
                        Rectangle {
                            x:4*root.scaleUnit; y:4*root.scaleUnit; width:parent.width-8*root.scaleUnit; height:58*root.scaleUnit
                            color:"#071009"; border.color:"#31513a"; border.width:1
                            Text { text:"INPUT MODE"; x:14*root.scaleUnit; y:8*root.scaleUnit; color:"#87958b"; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit) }
                            Text { text:bridge.bridgeMode==="CORE"?"OUTPUT ONLY":"PUSH TO TALK"; anchors.right:parent.right; anchors.rightMargin:14*root.scaleUnit; y:8*root.scaleUnit; color:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(13,17*root.scaleUnit) }
                            Text { text:bridge.bridgeMode==="CORE"?"BRIDGE SPEAKS ALERTS + CONFIRMATIONS // NO AI COMMAND INPUT":"PTT IS REQUIRED FOR COMMAND INPUT"; x:14*root.scaleUnit; y:33*root.scaleUnit; width:parent.width-28*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,11*root.scaleUnit) }
                        }
                        Text { text:bridge.bridgeMode==="CORE"?"TALK LEVEL":"AI PERSONALITY"; x:4*root.scaleUnit; y:76*root.scaleUnit; color:"#87958b"; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit) }
                        Row {
                            x:4*root.scaleUnit; y:98*root.scaleUnit; width:parent.width-8*root.scaleUnit; height:64*root.scaleUnit; spacing:8*root.scaleUnit
                            MechanicalButton { width:(parent.width-parent.spacing*2)/3; height:parent.height; text:"QUIET"; subtext:"ESSENTIAL / SAFETY"; active:bridge.voiceAttentionMode==="OFF"; stateful:true; accent:root.green; inactiveAccent:"#302817"; labelScale:.64; subtextMinSize:Math.max(9,10*root.scaleUnit); onClicked:{bridge.setVoiceAttention("OFF");bridge.playUiCue("confirm")} }
                            MechanicalButton { width:(parent.width-parent.spacing*2)/3; height:parent.height; text:"BALANCED"; subtext:"DEFAULT / OPERATIONAL"; active:bridge.voiceAttentionMode==="IMPORTANT"; stateful:true; accent:root.green; inactiveAccent:"#302817"; labelScale:.60; subtextMinSize:Math.max(9,10*root.scaleUnit); onClicked:{bridge.setVoiceAttention("IMPORTANT");bridge.playUiCue("confirm")} }
                            MechanicalButton { width:(parent.width-parent.spacing*2)/3; height:parent.height; text:"TALKATIVE"; subtext:"MOST ACTIVE"; active:bridge.voiceAttentionMode==="MOST"; stateful:true; accent:root.green; inactiveAccent:"#302817"; labelScale:.57; subtextMinSize:Math.max(9,10*root.scaleUnit); onClicked:{bridge.setVoiceAttention("MOST");bridge.playUiCue("confirm")} }
                        }
                        Row {
                            x:4*root.scaleUnit; y:174*root.scaleUnit; width:parent.width-8*root.scaleUnit; height:66*root.scaleUnit; spacing:10*root.scaleUnit
                            Column { width:(parent.width-parent.spacing)/2; height:parent.height; spacing:5*root.scaleUnit
                                Text { text:"VOICE"; color:"#87958b"; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,13*root.scaleUnit) }
                                CockpitComboBox { width:parent.width; height:46*root.scaleUnit; scaleUnit:root.scaleUnit; accentColor:root.green; textColor:root.whiteText; mutedColor:root.muted; model:bridge.voiceNameOptions; currentIndex:root.listIndexOf(bridge.voiceNameOptions,bridge.voiceName); onActivated:bridge.setVoiceTuning("name",currentText) }
                            }
                            Column { width:(parent.width-parent.spacing)/2; height:parent.height; spacing:5*root.scaleUnit
                                Text { text:"PITCH"; color:"#87958b"; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,13*root.scaleUnit) }
                                CockpitComboBox { width:parent.width; height:46*root.scaleUnit; scaleUnit:root.scaleUnit; accentColor:root.green; textColor:root.whiteText; mutedColor:root.muted; model:bridge.voicePitchOptions; currentIndex:root.listIndexOf(bridge.voicePitchOptions,bridge.voicePitch); onActivated:bridge.setVoiceTuning("pitch",currentText) }
                            }
                        }
                        Column { x:4*root.scaleUnit; y:250*root.scaleUnit; width:parent.width-8*root.scaleUnit; height:66*root.scaleUnit; spacing:5*root.scaleUnit
                            Text { text:"VOICE CHARACTER"; color:"#87958b"; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,13*root.scaleUnit) }
                            CockpitComboBox { width:parent.width; height:46*root.scaleUnit; scaleUnit:root.scaleUnit; accentColor:root.green; textColor:root.whiteText; mutedColor:root.muted; model:bridge.voiceEffectOptions; currentIndex:root.listIndexOf(bridge.voiceEffectOptions,bridge.voiceEffect); onActivated:bridge.setVoiceTuning("effect",currentText) }
                        }
                        Text { text:"EFFECT STRENGTH"; x:4*root.scaleUnit; y:326*root.scaleUnit; color:"#87958b"; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,13*root.scaleUnit) }
                        Text { text:bridge.voiceEffectStrength+"%"; anchors.right:parent.right; anchors.rightMargin:4*root.scaleUnit; y:326*root.scaleUnit; color:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit) }
                        Slider { id:effectStrengthSlider; x:4*root.scaleUnit; y:346*root.scaleUnit; width:parent.width-8*root.scaleUnit; from:0; to:100; stepSize:1; value:bridge.voiceEffectStrength; onPressedChanged:if(!pressed)bridge.setVoiceTuningNumber("effect_strength",value) }
                        Text { text:"SPEECH SPEED"; x:4*root.scaleUnit; y:394*root.scaleUnit; color:"#87958b"; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,13*root.scaleUnit) }
                        Text { text:bridge.voiceSpeedText; anchors.right:parent.right; anchors.rightMargin:4*root.scaleUnit; y:394*root.scaleUnit; color:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit) }
                        Slider { id:voiceSpeedSlider; x:4*root.scaleUnit; y:414*root.scaleUnit; width:parent.width-8*root.scaleUnit; from:.7; to:2.0; stepSize:.05; value:bridge.voiceSpeed; onPressedChanged:if(!pressed)bridge.setVoiceTuningNumber("speed",value) }
                        Text { text:"SCROLL FOR FULL VOICE TUNING"; x:4*root.scaleUnit; y:466*root.scaleUnit; width:parent.width-8*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,10*root.scaleUnit); horizontalAlignment:Text.AlignHCenter }
                    }
                }
            }

            MetalPanel {
                width:aiBottom.width*.35; height:aiBottom.height; panelColor:root.screen
                SectionTitle { text:"AI CONTROL / SESSION RULES"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }
                Column {
                    x:20*root.scaleUnit; y:64*root.scaleUnit; width:parent.width-40*root.scaleUnit; spacing:9*root.scaleUnit
                    Text { text:"ACTION MODE"; width:parent.width; color:root.amber; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,13*root.scaleUnit) }
                    Row { width:parent.width; height:92*root.scaleUnit; spacing:7*root.scaleUnit
                        MechanicalButton { width:(parent.width-parent.spacing*2)/3; height:parent.height; text:"SUGGEST ONLY"; subtext:"ADVICE // NO ACTION"; stateful:true; active:bridge.aiToolMode==="Suggest Only"; accent:root.green; labelScale:.50; subtextMinSize:Math.max(8,9*root.scaleUnit); onClicked:bridge.setSetupValue("ai_tool_mode","Suggest Only") }
                        MechanicalButton { width:(parent.width-parent.spacing*2)/3; height:parent.height; text:"ASK BEFORE ACTING"; subtext:"APPROVAL REQUIRED"; stateful:true; active:bridge.aiToolMode==="Ask Before Acting"; accent:root.green; labelScale:.45; subtextMinSize:Math.max(8,9*root.scaleUnit); onClicked:bridge.setSetupValue("ai_tool_mode","Ask Before Acting") }
                        MechanicalButton { width:(parent.width-parent.spacing*2)/3; height:parent.height; text:"AUTO NAVIGATION"; subtext:"ALLOWED AUTO ACTIONS"; stateful:true; active:bridge.aiToolMode==="Auto Navigation"; accent:root.green; labelScale:.46; subtextMinSize:Math.max(8,9*root.scaleUnit); onClicked:bridge.setSetupValue("ai_tool_mode","Auto Navigation") }
                    }
                    FlipSwitch { width:parent.width; height:Math.max(62,72*root.scaleUnit); scaleUnit:root.scaleUnit; text:"AUTOMATIC AI ASSISTANCE"; subtext:checked?"BACKGROUND EVENT ADVISOR ENABLED":"OFF // MANUAL AI STILL AVAILABLE"; checked:bridge.aiSmartAutoEnabled; accent:root.green; onToggled:function(requestedChecked){bridge.setSetupBool("ai_smart_auto",requestedChecked)} }
                    Rectangle { width:parent.width; height:54*root.scaleUnit; color:"#080b08"; border.color:bridge.aiPendingActionAvailable?root.amber:"#283229"; border.width:1; Text{text:"PENDING // "+bridge.aiPendingAction; x:10*root.scaleUnit; y:8*root.scaleUnit; width:parent.width-20*root.scaleUnit; color:bridge.aiPendingActionAvailable?root.amber:root.green; font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(10,13*root.scaleUnit);elide:Text.ElideRight} Text{text:"SESSION RULES ACTIVE // "+bridge.aiSessionRuleCount; x:10*root.scaleUnit; y:29*root.scaleUnit; width:parent.width-20*root.scaleUnit; color:"#7f8b82"; font.family:"Consolas";font.pixelSize:Math.max(10,11*root.scaleUnit)} }
                }
                Text { text:"PERSISTENT SETTINGS SURVIVE RESTART. SESSION RULES CLEAR WHEN BRIDGE EXITS."; x:22*root.scaleUnit; y:parent.height-44*root.scaleUnit; width:parent.width-44*root.scaleUnit; color:"#7f8b82"; font.family:"Consolas"; font.pixelSize:Math.max(10,11*root.scaleUnit); horizontalAlignment:Text.AlignHCenter; wrapMode:Text.WordWrap }
            }

            MetalPanel {
                width:aiBottom.width-aiBottom.children[0].width-aiBottom.children[1].width-root.gap*2; height:aiBottom.height; panelColor:root.screen
                SectionTitle { text:"AI / VOICE ACTIONS"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }
                Grid {
                    x:20*root.scaleUnit; y:66*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:parent.height-88*root.scaleUnit
                    columns:2; rows:2; columnSpacing:10*root.scaleUnit; rowSpacing:10*root.scaleUnit
                    MechanicalButton { width:(parent.width-parent.columnSpacing)/2; height:(parent.height-parent.rowSpacing)/2; text:"APPROVE AI ACTION"; subtext:bridge.aiPendingActionAvailable?"RUN THE ACTION WAITING ABOVE":"ONLY USED IN ASK-BEFORE-ACTING MODE"; accent:bridge.aiPendingActionAvailable?root.green:root.muted; labelScale:.62; onClicked:if(bridge.aiPendingActionAvailable)bridge.requestCommand("ai_approve") }
                    MechanicalButton { width:(parent.width-parent.columnSpacing)/2; height:(parent.height-parent.rowSpacing)/2; text:"REJECT AI ACTION"; subtext:bridge.aiPendingActionAvailable?"DISCARD THE ACTION WAITING ABOVE":"ONLY USED IN ASK-BEFORE-ACTING MODE"; accent:bridge.aiPendingActionAvailable?root.red:root.muted; labelScale:.62; onClicked:if(bridge.aiPendingActionAvailable)bridge.requestCommand("ai_reject") }
                    MechanicalButton { width:(parent.width-parent.columnSpacing)/2; height:(parent.height-parent.rowSpacing)/2; text:"OPEN CONTROLS"; subtext:"PTT / SHORTCUTS / ELITE BINDS"; accent:root.green; labelScale:.66; onClicked:{root.currentPage=10;controlsScroll.contentY=0} }
                    MechanicalButton { width:(parent.width-parent.columnSpacing)/2; height:(parent.height-parent.rowSpacing)/2; text:"CLEAR SESSION RULES"; subtext:bridge.aiSessionRuleCount>0?("CLEAR "+bridge.aiSessionRuleCount+" TEMPORARY RULE(S)"):"NO TEMPORARY RULES ACTIVE"; accent:bridge.aiSessionRuleCount>0?root.amber:root.muted; labelScale:.58; onClicked:if(bridge.aiSessionRuleCount>0)bridge.requestCommand("clear_rules") }
                }
            }
        }
    }


    // AUDIO MODULE: routing/mix/SFX control room with AI usage telemetry.
    Item {
        id: audioPage
        visible: root.currentPage === 7
        x: identity.x
        y: setupSectionTabs.y + setupSectionTabs.height + root.gap
        width: identity.width
        height: root.height - y - root.m
        property string pendingImportKey: bridge.audioSfxSelectedKey

        FileDialog {
            id: sfxFileDialog
            title: "Assign WAV sound to " + bridge.audioSfxSelectedLabel
            fileMode: FileDialog.OpenFile
            nameFilters: ["WAV audio (*.wav)", "All files (*)"]
            onAccepted: bridge.importSfxFile(audioPage.pendingImportKey, selectedFile.toString())
        }

        Row {
            id: audioTop
            width: parent.width
            height: parent.height * .64
            spacing: root.gap

            MetalPanel {
                width: audioTop.width * .30
                height: audioTop.height
                panelColor: root.screen
                SectionTitle { text: "AUDIO ROUTING"; x: 20*root.scaleUnit; y: 15*root.scaleUnit; width: parent.width-40*root.scaleUnit; height: 36*root.scaleUnit }

                Text { text: "OUTPUT DEVICE  //  CLICK TO SELECT"; x: 28*root.scaleUnit; y: 64*root.scaleUnit; color: "#87958b"; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit) }
                CockpitComboBox {
                    id: outputDeviceCombo
                    x: 28*root.scaleUnit; y: 86*root.scaleUnit; width: parent.width-56*root.scaleUnit; height: 56*root.scaleUnit
                    scaleUnit: root.scaleUnit; accentColor: root.green; textColor: root.whiteText; mutedColor: root.muted
                    model: bridge.audioOutputDevices
                    currentIndex: root.listIndexOf(bridge.audioOutputDevices, bridge.voiceOutputDevice)
                    onActivated: bridge.setAudioDevice("output", currentText)
                }
                Text { text: "WINDOWS DEFAULT // "+bridge.audioDefaultOutput; x:28*root.scaleUnit; y:148*root.scaleUnit; width:parent.width-56*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,11*root.scaleUnit); elide:Text.ElideRight }

                Text { text: "MICROPHONE  //  CLICK TO SELECT"; x: 28*root.scaleUnit; y: 183*root.scaleUnit; color: "#87958b"; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit) }
                CockpitComboBox {
                    id: inputDeviceCombo
                    x: 28*root.scaleUnit; y: 205*root.scaleUnit; width: parent.width-56*root.scaleUnit; height: 56*root.scaleUnit
                    scaleUnit: root.scaleUnit; accentColor: root.green; textColor: root.whiteText; mutedColor: root.muted
                    model: bridge.audioInputDevices
                    currentIndex: root.listIndexOf(bridge.audioInputDevices, bridge.voiceInputDevice)
                    onActivated: bridge.setAudioDevice("input", currentText)
                }
                Text { text: "WINDOWS DEFAULT // "+bridge.audioDefaultInput; x:28*root.scaleUnit; y:267*root.scaleUnit; width:parent.width-56*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,11*root.scaleUnit); elide:Text.ElideRight }

                Column {
                    x: 28*root.scaleUnit; y: 303*root.scaleUnit; width: parent.width-56*root.scaleUnit; spacing: 8*root.scaleUnit
                    Item { width:parent.width; height:30*root.scaleUnit; Text{text:"VOICE ENGINE";color:"#87958b";font.family:"Consolas";font.pixelSize:Math.max(11,14*root.scaleUnit);anchors.left:parent.left;anchors.verticalCenter:parent.verticalCenter} Text{text:bridge.voiceEngineMode+" // "+bridge.voiceName;color:root.whiteText;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(11,14*root.scaleUnit);anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter;width:parent.width*.62;horizontalAlignment:Text.AlignRight;elide:Text.ElideRight} }
                }

                Row {
                    x:28*root.scaleUnit; y:parent.height-88*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:64*root.scaleUnit; spacing:10*root.scaleUnit
                    MechanicalButton { width:(parent.width-parent.spacing)/2; height:parent.height; text:"RESCAN DEVICES"; subtext:"REFRESH WINDOWS AUDIO"; accent:root.amber; labelScale:.64; onClicked:bridge.requestCommand("audio_rescan") }
                    MechanicalButton { width:(parent.width-parent.spacing)/2; height:parent.height; text:"OPEN SETUP"; subtext:"GUIDED CONFIG"; accent:root.green; labelScale:.70; onClicked:{root.currentPage=8;setupScroll.contentY=0} }
                }
            }

            MetalPanel {
                width: audioTop.width * .48
                height: audioTop.height
                panelColor: root.screen
                SectionTitle { text: "SOUND EFFECTS  //  ASSIGN + TEST"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }
                Text { text:"SELECT A ROW // CLICK ITS FILE TO BROWSE // TOGGLE EACH EVENT AT RIGHT"; x:28*root.scaleUnit; y:53*root.scaleUnit; width:parent.width-56*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,11*root.scaleUnit) }
                Row {
                    x:28*root.scaleUnit; y:76*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:24*root.scaleUnit
                    Text { text:"EVENT"; width:parent.width*.34; color:"#718178"; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,13*root.scaleUnit) }
                    Text { text:"ASSIGNED FILE"; width:parent.width*.48; color:"#718178"; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,13*root.scaleUnit) }
                    Text { text:"ON / OFF"; width:parent.width*.18; color:"#718178"; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,13*root.scaleUnit); horizontalAlignment:Text.AlignHCenter }
                }
                Flickable {
                    id:sfxListScroll
                    x:28*root.scaleUnit; y:101*root.scaleUnit; width:parent.width-56*root.scaleUnit
                    height:Math.max(90*root.scaleUnit, parent.height-270*root.scaleUnit)
                    clip:true; contentWidth:width; contentHeight:sfxRowsColumn.height; boundsBehavior:Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    Column {
                        id:sfxRowsColumn; width:sfxListScroll.width-12*root.scaleUnit; spacing:4*root.scaleUnit
                        Repeater {
                            model: bridge.audioSfxRows
                        Rectangle {
                            id:sfxRow
                            width:parent.width; height:38*root.scaleUnit
                            property bool selected: modelData.key === bridge.audioSfxSelectedKey
                            color:selected?"#0a1c11":(rowMouse.containsMouse?"#0b140d":"#080a08")
                            border.color:selected?root.green:(rowMouse.containsMouse?"#407851":"#202a22")
                            border.width:selected?2:1
                            Text { z:1; text:modelData.label; x:10*root.scaleUnit; width:parent.width*.32; anchors.verticalCenter:parent.verticalCenter; color:sfxRow.selected?root.green:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,13*root.scaleUnit); elide:Text.ElideRight }
                            Rectangle {
                                id:filePick
                                z:2
                                x:parent.width*.34; width:parent.width*.46; height:parent.height-6*root.scaleUnit; anchors.verticalCenter:parent.verticalCenter
                                color:fileMouse.containsMouse?"#132018":"#0a0d0a"; border.color:fileMouse.containsMouse?root.green:"#2d3a30"; border.width:1
                                Text { text:modelData.file+"  ["+modelData.source+"]"; x:8*root.scaleUnit; width:parent.width-24*root.scaleUnit; anchors.verticalCenter:parent.verticalCenter; color:fileMouse.containsMouse?root.green:"#a5ada6"; font.family:"Consolas"; font.pixelSize:Math.max(10,12*root.scaleUnit); elide:Text.ElideRight }
                                Text { text:"…"; anchors.right:parent.right; anchors.rightMargin:7*root.scaleUnit; anchors.verticalCenter:parent.verticalCenter; color:fileMouse.containsMouse?root.green:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(13,17*root.scaleUnit) }
                                MouseArea { id:fileMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; onClicked:{ bridge.selectSfxEvent(modelData.key); audioPage.pendingImportKey=modelData.key; sfxFileDialog.open() } }
                            }
                            Rectangle {
                                id:miniSwitch
                                z:2
                                width:Math.max(72,82*root.scaleUnit); height:Math.max(24,28*root.scaleUnit); radius:height/2
                                anchors.right:parent.right; anchors.rightMargin:8*root.scaleUnit; anchors.verticalCenter:parent.verticalCenter
                                color:"#111510"; border.color:modelData.enabled?root.green:"#555b53"; border.width:2
                                Text { text:modelData.enabled?"ON":"OFF"; anchors.centerIn:parent; color:modelData.enabled?root.green:"#b9b6aa"; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,12*root.scaleUnit) }
                                MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked:{ bridge.selectSfxEvent(modelData.key); bridge.setSfxEventEnabled(modelData.key,!modelData.enabled) } }
                            }
                            MouseArea { id:rowMouse; anchors.fill:parent; anchors.rightMargin:Math.max(90,100*root.scaleUnit); hoverEnabled:true; cursorShape:Qt.PointingHandCursor; z:0; onClicked:bridge.selectSfxEvent(modelData.key) }
                        }
                    }
                }
                }

                Rectangle {
                    x:28*root.scaleUnit; y:parent.height-154*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:48*root.scaleUnit
                    color:"#061008"; border.color:root.green; border.width:1
                    Text { text:bridge.audioSfxSelectedLabel; x:12*root.scaleUnit; y:7*root.scaleUnit; width:parent.width*.42; color:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit); elide:Text.ElideRight }
                    Text { text:bridge.audioSfxSelectedFile+" // "+bridge.audioSfxSelectedSource; anchors.right:parent.right; anchors.rightMargin:12*root.scaleUnit; y:7*root.scaleUnit; width:parent.width*.52; horizontalAlignment:Text.AlignRight; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(10,13*root.scaleUnit); elide:Text.ElideRight }
                    Text { text:"SELECTED EVENT // "+(bridge.audioSfxSelectedEnabled?"ON":"OFF"); x:12*root.scaleUnit; y:27*root.scaleUnit; width:parent.width-24*root.scaleUnit; color:bridge.audioSfxSelectedEnabled?root.green:root.amber; font.family:"Consolas"; font.pixelSize:Math.max(10,11*root.scaleUnit) }
                }
                Row {
                    x:28*root.scaleUnit; y:parent.height-96*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:68*root.scaleUnit; spacing:10*root.scaleUnit
                    MechanicalButton { width:(parent.width-parent.spacing*2)/3; height:parent.height; text:"BROWSE / ASSIGN"; subtext:"CHOOSE WAV FILE"; accent:root.green; labelScale:.58; onClicked:{ audioPage.pendingImportKey=bridge.audioSfxSelectedKey; sfxFileDialog.open() } }
                    MechanicalButton { width:(parent.width-parent.spacing*2)/3; height:parent.height; text:"PLAY SELECTED"; subtext:"TEST THIS EVENT"; accent:root.green; labelScale:.62; onClicked:bridge.testSfxEvent(bridge.audioSfxSelectedKey) }
                    MechanicalButton { width:(parent.width-parent.spacing*2)/3; height:parent.height; text:"RESTORE DEFAULT"; subtext:"REMOVE CUSTOM WAV"; accent:root.amber; labelScale:.55; onClicked:bridge.resetSfxEvent(bridge.audioSfxSelectedKey) }
                }
            }

            MetalPanel {
                width: audioTop.width - audioTop.children[0].width - audioTop.children[1].width - root.gap*2
                height: audioTop.height
                panelColor: root.screen
                SectionTitle { text:"OUTPUT / AI MONITOR"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }
                VoiceWave { x:28*root.scaleUnit; y:70*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:88*root.scaleUnit; color:root.green; activeColor:root.amber; speaking:bridge.voiceMode==="SPEAKING"; listening:bridge.voiceMode!=="SPEAKING"; phase:bridge.pulse }
                Text { text:bridge.voiceMode==="SPEAKING"?"SPEAKING":"VOICE READY"; x:28*root.scaleUnit; y:170*root.scaleUnit; width:parent.width-56*root.scaleUnit; color:bridge.voiceMode==="SPEAKING"?root.amber:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(14,19*root.scaleUnit); horizontalAlignment:Text.AlignHCenter }
                Column {
                    x:28*root.scaleUnit; y:220*root.scaleUnit; width:parent.width-56*root.scaleUnit; spacing:9*root.scaleUnit
                    StatusLamp { width:parent.width; height:36*root.scaleUnit; label:"SOUND EFFECTS"; value:bridge.voiceSfxEnabled?"READY":"MASTER OFF"; stateColor:bridge.voiceSfxEnabled?root.green:root.amber; pulse:false; phase:bridge.pulse; fontScale:1.05 }
                    StatusLamp { width:parent.width; height:36*root.scaleUnit; label:"LAST SOUND"; value:bridge.audioLastSound; stateColor:root.whiteText; pulse:false; phase:bridge.pulse; fontScale:1.05 }
                    StatusLamp { width:parent.width; height:36*root.scaleUnit; label:"AI TOTAL COST"; value:bridge.aiUsageEstimatedCostText; stateColor:root.green; pulse:false; phase:bridge.pulse; fontScale:1.05 }
                    StatusLamp { width:parent.width; height:36*root.scaleUnit; label:"AI TOKENS"; value:root.fmtNumber(bridge.aiUsageInputTokens+bridge.aiUsageOutputTokens); stateColor:root.whiteText; pulse:false; phase:bridge.pulse; fontScale:1.05 }
                    StatusLamp { width:parent.width; height:36*root.scaleUnit; label:"TRANSCRIBED"; value:bridge.aiUsageTranscriptionSecondsText; stateColor:root.whiteText; pulse:false; phase:bridge.pulse; fontScale:1.05 }
                }
            }
        }

        Row {
            id:audioBottom
            x:0; y:audioTop.height+root.gap; width:parent.width; height:parent.height-y; spacing:root.gap

            MetalPanel {
                width:audioBottom.width*.34; height:audioBottom.height; panelColor:root.screen
                SectionTitle { text:"VOICE PROFILE"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }
                Rectangle { x:28*root.scaleUnit; y:68*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:72*root.scaleUnit; color:"#061008"; border.color:"#31513a"; border.width:1
                    Text { text:bridge.voiceName+" // "+bridge.voiceEngineMode; x:12*root.scaleUnit; y:9*root.scaleUnit; width:parent.width-24*root.scaleUnit; color:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(14,19*root.scaleUnit); elide:Text.ElideRight }
                    Text { text:"PITCH "+bridge.voicePitch+"  //  "+bridge.voiceEffect+" "+bridge.voiceEffectStrength+"%  //  "+bridge.voiceSpeedText; x:12*root.scaleUnit; y:40*root.scaleUnit; width:parent.width-24*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(10,13*root.scaleUnit); elide:Text.ElideRight }
                }
                Text { text:"VOICE CHARACTER LIVES IN AI & VOICE. AUDIO HANDLES ROUTING, LEVELS AND SOUND EFFECTS."; x:28*root.scaleUnit; y:153*root.scaleUnit; width:parent.width-56*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,11*root.scaleUnit); wrapMode:Text.WordWrap; horizontalAlignment:Text.AlignHCenter }
                Row { x:28*root.scaleUnit; y:parent.height-92*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:68*root.scaleUnit; spacing:10*root.scaleUnit
                    MechanicalButton { width:(parent.width-parent.spacing)/2; height:parent.height; text:"OPEN VOICE TUNING"; subtext:"PITCH / CHARACTER / SPEED"; accent:root.green; labelScale:.55; onClicked:root.currentPage=6 }
                    MechanicalButton { width:(parent.width-parent.spacing)/2; height:parent.height; text:"VOICE TEST"; subtext:"PLAY CURRENT PROFILE"; accent:root.green; labelScale:.68; onClicked:{bridge.playUiCue("nav");bridge.requestCommand("voice_test")} }
                }
            }

            MetalPanel {
                width:audioBottom.width*.36; height:audioBottom.height; panelColor:root.screen
                SectionTitle { text:"MIX LEVELS"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }
                Text { text:"VOICE VOLUME"; x:28*root.scaleUnit; y:72*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(13,17*root.scaleUnit) }
                Text { text:bridge.voiceVolume+"%"; anchors.right:parent.right; anchors.rightMargin:28*root.scaleUnit; y:72*root.scaleUnit; color:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(13,17*root.scaleUnit) }
                Slider { id:voiceSlider; x:28*root.scaleUnit; y:105*root.scaleUnit; width:parent.width-56*root.scaleUnit; from:0; to:100; stepSize:1; value:bridge.voiceVolume; onPressedChanged: if (!pressed) bridge.setAudioLevel("voice",Math.round(value)) }

                Text { text:"SFX VOLUME"; x:28*root.scaleUnit; y:158*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(13,17*root.scaleUnit) }
                Text { text:bridge.audioSfxVolume+"%"; anchors.right:parent.right; anchors.rightMargin:28*root.scaleUnit; y:158*root.scaleUnit; color:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(13,17*root.scaleUnit) }
                Slider { id:sfxSlider; x:28*root.scaleUnit; y:191*root.scaleUnit; width:parent.width-56*root.scaleUnit; from:0; to:100; stepSize:1; value:bridge.audioSfxVolume; onPressedChanged: if (!pressed) bridge.setAudioLevel("sfx",Math.round(value)) }

                Text { text:"DRAG A LEVEL, THEN RELEASE TO SAVE"; x:28*root.scaleUnit; y:238*root.scaleUnit; width:parent.width-56*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,11*root.scaleUnit); horizontalAlignment:Text.AlignHCenter }
            }

            MetalPanel {
                width:audioBottom.width-audioBottom.children[0].width-audioBottom.children[1].width-root.gap*2; height:audioBottom.height; panelColor:root.screen
                SectionTitle { text:"AUDIO STATUS"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }
                Column { x:24*root.scaleUnit; y:70*root.scaleUnit; width:parent.width-48*root.scaleUnit; spacing:12*root.scaleUnit
                    Item { width:parent.width; height:34*root.scaleUnit; Text{text:"SFX MASTER";color:"#87958b";font.family:"Consolas";font.pixelSize:Math.max(11,14*root.scaleUnit);anchors.left:parent.left;anchors.verticalCenter:parent.verticalCenter} Text{text:bridge.voiceSfxEnabled?"ON":"OFF";color:bridge.voiceSfxEnabled?root.green:root.amber;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(12,15*root.scaleUnit);anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter} }
                    Item { width:parent.width; height:34*root.scaleUnit; Text{text:"SELECTED EVENT";color:"#87958b";font.family:"Consolas";font.pixelSize:Math.max(11,14*root.scaleUnit);anchors.left:parent.left;anchors.verticalCenter:parent.verticalCenter} Text{text:bridge.audioSfxSelectedEnabled?"ENABLED":"DISABLED";color:bridge.audioSfxSelectedEnabled?root.green:root.amber;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(11,14*root.scaleUnit);anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter} }
                    Text { text:bridge.audioSfxStatus; width:parent.width; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(10,13*root.scaleUnit); wrapMode:Text.WordWrap; maximumLineCount:3 }
                }
                MechanicalButton { x:24*root.scaleUnit; y:parent.height-92*root.scaleUnit; width:parent.width-48*root.scaleUnit; height:68*root.scaleUnit; text:"OPEN CONTROLS"; subtext:"PTT / HOTAS / BINDS"; accent:root.green; labelScale:.64; onClicked:{root.currentPage=10;controlsScroll.contentY=0} }
            }
        }
    }


    // CONTROLS: all Bridge input mapping and Elite bind health lives here.
    Item {
        id: controlsPage
        visible: root.currentPage === 10
        x: identity.x
        y: setupSectionTabs.y + setupSectionTabs.height + root.gap
        width: identity.width
        height: root.height - y - root.m

        Flickable {
            id: controlsScroll
            anchors.fill:parent; clip:true; contentWidth:width; contentHeight:controlsColumn.height+100*root.scaleUnit
            boundsBehavior:Flickable.StopAtBounds; ScrollBar.vertical:ScrollBar { policy:ScrollBar.AlwaysOn }
            Column {
                id:controlsColumn; width:controlsScroll.width-22*root.scaleUnit; spacing:28*root.scaleUnit

                MetalPanel { id:controlsPttPanel; width:parent.width; height:430*root.scaleUnit; panelColor:root.screen
                    SectionTitle { text:"PUSH-TO-TALK / INPUT STATUS // REQUIRED"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }
                    Rectangle { x:28*root.scaleUnit; y:68*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:92*root.scaleUnit; color:"#061008"; border.color:bridge.pttStatus==="NOT MAPPED"?root.red:root.green; border.width:1
                        Text{text:"◆ REQUIRED PTT // "+(bridge.pttStatus==="NOT MAPPED"?"NOT MAPPED // SET A PTT CONTROL TO CONTINUE":"MAPPED // READY");x:16*root.scaleUnit;y:12*root.scaleUnit;color:bridge.pttStatus==="NOT MAPPED"?root.amber:root.green;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(13,17*root.scaleUnit)}
                        Text{text:bridge.voicePttMapping;x:16*root.scaleUnit;y:42*root.scaleUnit;width:parent.width-32*root.scaleUnit;color:root.whiteText;font.family:"Consolas";font.pixelSize:Math.max(11,14*root.scaleUnit);elide:Text.ElideRight}
                        Text{text:"KEYBOARD FALLBACK // CTRL + ALT + SHIFT + V";x:16*root.scaleUnit;y:66*root.scaleUnit;width:parent.width-32*root.scaleUnit;color:root.muted;font.family:"Consolas";font.pixelSize:Math.max(10,11*root.scaleUnit);elide:Text.ElideRight}
                    }
                    Row { x:28*root.scaleUnit; y:180*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:86*root.scaleUnit; spacing:12*root.scaleUnit
                        MechanicalButton { width:(parent.width-parent.spacing)/2; height:parent.height; text:"MIC CHECK"; subtext:"5 SEC LOCAL INPUT"; accent:root.green; labelScale:.78; onClicked:bridge.requestCommand("mic_test") }
                        MechanicalButton { width:(parent.width-parent.spacing)/2; height:parent.height; text:"TRANSCRIPTION TEST"; subtext:"5 SEC // WHAT AI HEARS"; accent:root.green; labelScale:.64; onClicked:bridge.requestCommand("hearing_test") }
                    }
                    Rectangle { x:28*root.scaleUnit; y:286*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:112*root.scaleUnit; color:"#050b07"; border.color:"#244a30"; border.width:1
                        Text{text:"INPUT STATUS";x:14*root.scaleUnit;y:10*root.scaleUnit;color:root.muted;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(10,13*root.scaleUnit)}
                        Text{text:bridge.voiceInputStatus;x:14*root.scaleUnit;y:38*root.scaleUnit;width:parent.width-28*root.scaleUnit;color:root.whiteText;font.family:"Consolas";font.pixelSize:Math.max(11,13*root.scaleUnit);wrapMode:Text.WordWrap}
                        Text{text:"LAST TRANSCRIPT // "+bridge.voiceLastText;x:14*root.scaleUnit;y:78*root.scaleUnit;width:parent.width-28*root.scaleUnit;color:bridge.voiceLastText!=="-"?root.green:root.muted;font.family:"Consolas";font.pixelSize:Math.max(10,12*root.scaleUnit);elide:Text.ElideRight}
                    }
                }

                MetalPanel { id:controlsCommandMapPanel; width:parent.width; height:690*root.scaleUnit; panelColor:root.screen
                    SectionTitle { text:"BRIDGE COMMAND MAP // DIRECT KEYBOARD + HOTAS REMAP"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }
                    Text { text:"KEYBOARD: CLICK THE FIELD. HOTAS / CONTROLLER: USE REMAP. CLICK CLEAR TO REMOVE A BINDING."; x:28*root.scaleUnit; y:56*root.scaleUnit; width:parent.width-56*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,12*root.scaleUnit); wrapMode:Text.WordWrap }
                    Text { text:"CAPTURE // "+bridge.controlCaptureStatus; x:28*root.scaleUnit; y:82*root.scaleUnit; width:parent.width-56*root.scaleUnit; color:bridge.controlCaptureStatus.indexOf("WAIT")>=0?root.amber:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,11*root.scaleUnit); elide:Text.ElideRight }
                    Rectangle { x:28*root.scaleUnit; y:108*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:38*root.scaleUnit; color:"#07100a"; border.color:"#244a30"; border.width:1
                        Text{text:"COMMAND";x:12*root.scaleUnit;width:parent.width*.29;anchors.verticalCenter:parent.verticalCenter;color:root.muted;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(10,12*root.scaleUnit)}
                        Text{text:"KEYBOARD";x:parent.width*.31;width:parent.width*.27;anchors.verticalCenter:parent.verticalCenter;color:root.muted;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(10,12*root.scaleUnit)}
                        Text{text:"HOTAS / CONTROLLER";x:parent.width*.59;width:parent.width*.27;anchors.verticalCenter:parent.verticalCenter;color:root.muted;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(10,12*root.scaleUnit)}
                        Text{text:"CLEAR";x:parent.width*.88;width:parent.width*.10;anchors.verticalCenter:parent.verticalCenter;color:root.muted;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(9,11*root.scaleUnit);horizontalAlignment:Text.AlignHCenter}
                    }
                    Flickable {
                        id: commandMapScroll; x:28*root.scaleUnit; y:150*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:parent.height-y-28*root.scaleUnit
                        clip:true; contentWidth:width; contentHeight:commandRows.height; boundsBehavior:Flickable.StopAtBounds
                        ScrollBar.vertical:ScrollBar { policy:ScrollBar.AlwaysOn }
                        Column { id:commandRows; width:commandMapScroll.width-18*root.scaleUnit; spacing:4*root.scaleUnit
                            Repeater { model:bridge.setupControlRows
                                Rectangle {
                                    property int commandRowIndex: index
                                    width:parent.width; height:54*root.scaleUnit; color:"#050b07"
                                    border.color:modelData.eliteConflict?root.red:(modelData.required && modelData.hotkeyState!=="READY"?root.amber:"#1c3927"); border.width:modelData.eliteConflict?2:1
                                    Text{text:(modelData.required?"◆  ":"")+modelData.label;x:10*root.scaleUnit;width:parent.width*.28;anchors.verticalCenter:parent.verticalCenter;color:modelData.required?root.green:root.whiteText;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(9,11*root.scaleUnit);elide:Text.ElideRight}
                                    Rectangle {
                                        x:parent.width*.30; y:6*root.scaleUnit; width:parent.width*.27; height:parent.height-12*root.scaleUnit
                                        property bool mapped:modelData.hotkeyState==="READY"
                                        property bool hovered:keyboardMapMouse.containsMouse
                                        property bool pressed:keyboardMapMouse.pressed
                                        color:pressed?"#124c31":(hovered?"#0d3826":"#07110a")
                                        border.color:hovered?root.green2:(mapped?root.green:root.amber); border.width:hovered?2:1
                                        Text { anchors.fill:parent; anchors.margins:7*root.scaleUnit; verticalAlignment:Text.AlignVCenter; text:modelData.hotkey||"CLICK TO BIND"; color:parent.hovered?root.green2:(parent.mapped?root.green:root.amber); font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(9,11*root.scaleUnit); elide:Text.ElideRight }
                                        MouseArea { id:keyboardMapMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; onClicked:{bridge.playUiCue("confirm");bridge.beginBridgeHotkeyCaptureRowSafe(parent.parent.commandRowIndex)} }
                                    }
                                    Rectangle {
                                        property int commandRowIndex: parent.commandRowIndex
                                        x:parent.width*.59; y:6*root.scaleUnit; width:parent.width*.27; height:parent.height-12*root.scaleUnit
                                        property bool eliteConflict: Boolean(modelData.controllerConflict)
                                        property bool capturing: bridge.controlCaptureAction===String(modelData.id||modelData.commandId||"")
                                        property bool mapped:String(modelData.controllerState||"UNBOUND").toUpperCase()!=="UNBOUND" && String(modelData.controller||"NOT MAPPED").toUpperCase()!=="NOT MAPPED"
                                        color:eliteConflict?"#260807":"#07110a"
                                        border.color:capturing?root.amber:(eliteConflict?root.red:(mapped?root.green:root.amber))
                                        border.width:(capturing||eliteConflict)?2:1
                                        Text {
                                            x:7*root.scaleUnit; y:0; width:parent.width-92*root.scaleUnit; height:parent.height
                                            verticalAlignment:Text.AlignVCenter
                                            text:parent.capturing?"PRESS HOTAS / CONTROLLER CONTROL...":(modelData.controller||modelData.hotkeyController||modelData.joystick||"NOT MAPPED")
                                            color:parent.capturing?root.amber:(parent.eliteConflict?root.red:(parent.mapped?root.green:root.amber)); font.family:"Consolas"; font.bold:parent.capturing||parent.eliteConflict||parent.mapped
                                            font.pixelSize:Math.max(8,10*root.scaleUnit); elide:Text.ElideRight
                                        }
                                        Rectangle {
                                            anchors.right:parent.right; anchors.rightMargin:5*root.scaleUnit; anchors.verticalCenter:parent.verticalCenter
                                            width:78*root.scaleUnit; height:parent.height-10*root.scaleUnit
                                            property bool hovered: remapMouse.containsMouse
                                            property bool pressed: remapMouse.pressed
                                            color:parent.parent.capturing?"#2a1b07":(parent.parent.eliteConflict?(pressed?"#5a1110":(hovered?"#3b0d0b":"#260807")):(pressed?"#124c31":(hovered?"#0d3826":"#092016")))
                                            border.color:parent.parent.capturing?root.amber:(parent.parent.eliteConflict?root.red:(hovered?root.green2:root.green)); border.width:hovered?2:1
                                            Text { anchors.centerIn:parent; text:parent.parent.capturing?"WAIT":(parent.parent.eliteConflict?"CONFLICT":"REMAP"); color:parent.parent.capturing?root.amber:(parent.parent.eliteConflict?root.red:(parent.parent.hovered?root.green2:root.green)); font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(8,10*root.scaleUnit) }
                                            MouseArea {
                                                id:remapMouse
                                                anchors.fill:parent
                                                enabled:!parent.parent.capturing
                                                hoverEnabled:true
                                                cursorShape:Qt.PointingHandCursor
                                                onClicked:{
                                                    bridge.playUiCue("confirm")
                                                    bridge.bindBridgeControlRow(parent.parent.commandRowIndex)
                                                }
                                            }
                                        }
                                    }
                                    Rectangle {
                                        x:parent.width*.88; y:6*root.scaleUnit; width:parent.width*.10; height:parent.height-12*root.scaleUnit
                                        property bool hovered: clearMouse.containsMouse
                                        property bool pressed: clearMouse.pressed
                                        color:pressed?"#5a1110":(hovered?"#35100e":"#160908"); border.color:hovered?"#ff756d":root.red; border.width:hovered?2:1
                                        Text { anchors.centerIn:parent; text:"CLEAR"; color:parent.hovered?"#ff8b84":root.red; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(8,10*root.scaleUnit) }
                                        MouseArea {
                                            id:clearMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
                                            onClicked:{
                                                bridge.playUiCue("confirm")
                                                bridge.clearBridgeControlRow(parent.parent.commandRowIndex)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

MetalPanel { id:controlsEliteBindsPanel; width:parent.width; height:Math.max(620*root.scaleUnit,(270+bridge.setupEliteBindingRows.length*42)*root.scaleUnit); panelColor:root.screen
                    SectionTitle { text:"ELITE REQUIRED BINDINGS // READ ONLY"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }
                    Text { text:bridge.eliteBindingsLive?"BRIDGE READS YOUR ACTIVE ELITE .BINDS PROFILE AND FLAGS MISSING CONTROLS. FOR A MISSING KEY, BRIDGE CAN RECOMMEND AN UNUSED COMBINATION BASED ON YOUR CURRENT PROFILE. BRIDGE NEVER EDITS YOUR ELITE BINDS.":"NO ACTIVE ELITE .BINDS PROFILE DETECTED. ELITE-CONTROL FEATURES STAY UNAVAILABLE, BUT THE REST OF BRIDGE REMAINS USABLE."; x:28*root.scaleUnit; y:58*root.scaleUnit; width:parent.width-260*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,12*root.scaleUnit); wrapMode:Text.WordWrap }
                    MechanicalButton { x:parent.width-218*root.scaleUnit; y:54*root.scaleUnit; width:190*root.scaleUnit; height:58*root.scaleUnit; text:"RESCAN ELITE BINDS"; subtext:"ACTIVE PROFILE"; accent:root.green; labelScale:.70; onClicked:{bridge.playUiCue("nav");bridge.requestCommand("setup_binds")} }
                    Column { x:28*root.scaleUnit; y:128*root.scaleUnit; width:parent.width-56*root.scaleUnit; spacing:3*root.scaleUnit
                        Repeater { model:bridge.setupEliteBindingRows
                            Rectangle {
                                width:parent.width; height:46*root.scaleUnit
                                property bool ready:modelData.status==="READY"
                                color:ready?"#050b07":"#170807"; border.color:ready?"#1b6036":root.red; border.width:ready?1:2
                                Text{text:modelData.label;x:10*root.scaleUnit;width:parent.width*.29;anchors.verticalCenter:parent.verticalCenter;color:parent.ready?root.whiteText:root.red;font.family:"Consolas";font.pixelSize:Math.max(10,12*root.scaleUnit);elide:Text.ElideRight}
                                Text{text:modelData.status;x:parent.width*.30;width:parent.width*.11;anchors.verticalCenter:parent.verticalCenter;color:parent.ready?root.green:root.red;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(10,12*root.scaleUnit)}
                                Text{
                                    text:parent.ready?modelData.detail:("RECOMMENDED // "+(modelData.suggestion||"NO SAFE SUGGESTION"))
                                    x:parent.width*.42;width:parent.width*.44;anchors.verticalCenter:parent.verticalCenter
                                    color:parent.ready?root.muted:root.amber;font.family:"Consolas";font.bold:!parent.ready;font.pixelSize:Math.max(9,11*root.scaleUnit);elide:Text.ElideRight
                                }
                                Rectangle {
                                    visible:!parent.ready && Boolean(modelData.suggestion)
                                    x:parent.width*.87; width:parent.width*.12; height:parent.height-10*root.scaleUnit; anchors.verticalCenter:parent.verticalCenter
                                    property bool hovered:copySuggestMouse.containsMouse
                                    property bool pressed:copySuggestMouse.pressed
                                    color:pressed?"#124c31":(hovered?"#0d3826":"#092016"); border.color:hovered?root.green2:root.green; border.width:hovered?2:1
                                    Text{anchors.centerIn:parent;text:"COPY";color:parent.hovered?root.green2:root.green;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(8,10*root.scaleUnit)}
                                    MouseArea{
                                        id:copySuggestMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor
                                        onClicked:{bridge.playUiCue("confirm");bridge.copyTextToClipboard(String(modelData.suggestion||""))}
                                    }
                                }
                            }
                        }
                    }
                }

                Item { width:1; height:80*root.scaleUnit }
            }
        }
    }


    // v0.30.40: lazy in-game overlay. Top layout places chat beside the HUD;
    // side layouts stack a taller chat panel below the activity HUD.
    Loader {
        id: gameOverlayLoader
        active: root.overlayRuntimeRequested
        sourceComponent: Component {
            Window {
                id: gameOverlay
                visible: true
                property string overlayMode: bridge.gameOverlayMode
                property string overlayPosition: bridge.gameOverlayPosition
                property string overlayLayout: bridge.gameOverlayLayout
                property string overlaySize: bridge.gameOverlaySize
                property real sizeFactor: overlaySize === "SMALL" ? 0.62 : (overlaySize === "LARGE" ? 1.42 : 1.0)
                property real panelOpacity: bridge.gameOverlayOpacity / 100.0
                property bool showActivity: overlayMode !== "CHAT"
                property bool showChat: overlayMode !== "ACTIVITY"
                property bool sideLayout: overlayLayout === "LEFT" || overlayLayout === "RIGHT"
                property int activityW: Math.round(360*sizeFactor)
                property int activityH: Math.round(92*sizeFactor)
                property int chatW: Math.round((sideLayout ? 390 : 520)*sizeFactor)
                property int chatH: Math.round((sideLayout ? 430 : 230)*sizeFactor)
                property int panelGap: Math.round(12*sizeFactor)
                width: sideLayout ? Math.max(showActivity?activityW:0, showChat?chatW:0) : (showActivity && showChat ? activityW+panelGap+chatW : (showChat?chatW:activityW))
                height: sideLayout ? (showActivity&&showChat ? activityH+panelGap+chatH : (showChat?chatH:activityH)) : Math.max(showActivity?activityH:0, showChat?chatH:0)
                color: "transparent"
                flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool | Qt.WindowTransparentForInput
                x: overlayPosition === "TOP_LEFT" ? 54 : (overlayPosition === "TOP_RIGHT" ? Screen.width-width-54 : (overlayPosition === "LEFT" ? 46 : (overlayPosition === "RIGHT" ? Screen.width-width-46 : Math.round((Screen.width-width)/2))))
                y: overlayPosition === "LEFT" || overlayPosition === "RIGHT" ? Math.round((Screen.height-height)/2) : 42
                property bool critical: String(bridge.bridgeLevel || "").toLowerCase() === "bad"
                property bool speaking: bridge.voiceMode === "SPEAKING"
                property bool listening: bridge.voiceMode === "LISTENING"
                property bool thinking: !critical && !speaking && !listening && (String(bridge.aiCopilotStatus || "").toUpperCase().indexOf("THINK") >= 0 || String(bridge.aiCopilotStatus || "").toUpperCase().indexOf("PROCESS") >= 0 || String(bridge.aiCopilotStatus || "").toUpperCase().indexOf("WORK") >= 0)
                property string commandFeedback: String(bridge.commandFeedbackState || "IDLE").toUpperCase()
                property bool commandFailed: commandFeedback === "FAILED"
                property bool commandDone: commandFeedback === "COMPLETED"
                property bool commanding: !critical && !speaking && !listening && !thinking && (commandFeedback === "EXECUTING" || String(bridge.controlOwner || "NONE").toUpperCase() !== "NONE")
                property color stateColor: critical || commandFailed ? "#ff493e" : (speaking ? "#ffad42" : (commanding ? "#e6b64c" : (commandDone ? "#58df88" : (thinking ? "#a98cff" : (listening ? "#55d7ff" : "#329ee8")))))
                property string stateText: critical ? "BRIDGE ALERT" : (commandFailed ? "COMMAND FAILED" : (speaking ? "AI SPEAKING" : (commanding ? "COMMAND ACTIVE" : (commandDone ? "COMMAND COMPLETE // CONTROL RETURNED" : (thinking ? "AI THINKING" : (listening ? "LISTENING" : "BRIDGE READY"))))))

                Rectangle {
                    id: activityPanel
                    visible: gameOverlay.showActivity
                    x: gameOverlay.sideLayout ? Math.round((gameOverlay.width-width)/2) : 0; y: 0
                    width: gameOverlay.activityW; height: gameOverlay.activityH
                    radius:Math.max(4,8*gameOverlay.sizeFactor); color:"#050A0D"; opacity:gameOverlay.panelOpacity
                    border.color:gameOverlay.stateColor; border.width:1
                    Rectangle { x:0; y:0; width:Math.max(3,5*gameOverlay.sizeFactor); height:parent.height; radius:3; color:gameOverlay.stateColor; opacity:.9 }
                    Text { text:gameOverlay.stateText; x:24*gameOverlay.sizeFactor; y:10*gameOverlay.sizeFactor; width:parent.width-48*gameOverlay.sizeFactor; height:20*gameOverlay.sizeFactor; color:gameOverlay.stateColor; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(9,14*gameOverlay.sizeFactor); horizontalAlignment:Text.AlignHCenter }
                    Row {
                        anchors.horizontalCenter:parent.horizontalCenter; y:42*gameOverlay.sizeFactor; spacing:Math.max(2,5*gameOverlay.sizeFactor)
                        Repeater { model:19; Rectangle { width:Math.max(4,8*gameOverlay.sizeFactor); height:{ var active=gameOverlay.speaking||gameOverlay.listening||gameOverlay.thinking||gameOverlay.commanding||gameOverlay.commandDone||gameOverlay.commandFailed||gameOverlay.critical; if(!active)return (5+((index%5)*2))*gameOverlay.sizeFactor; return (9+23*(0.5+0.5*Math.sin((bridge.pulse*12.56636)+(index*.72))))*gameOverlay.sizeFactor } anchors.verticalCenter:parent.verticalCenter; radius:2; color:gameOverlay.stateColor; opacity:gameOverlay.speaking||gameOverlay.listening||gameOverlay.thinking||gameOverlay.commanding||gameOverlay.commandDone||gameOverlay.commandFailed||gameOverlay.critical ? .9 : .48 } }
                    }
                }
                Rectangle {
                    id: overlayChat
                    visible: gameOverlay.showChat
                    x: gameOverlay.sideLayout ? Math.round((gameOverlay.width-width)/2) : (gameOverlay.showActivity ? gameOverlay.activityW+gameOverlay.panelGap : 0)
                    y: gameOverlay.sideLayout && gameOverlay.showActivity ? gameOverlay.activityH+gameOverlay.panelGap : 0
                    width:gameOverlay.chatW; height:gameOverlay.chatH; radius:Math.max(4,8*gameOverlay.sizeFactor)
                    color:"#050907"; opacity:gameOverlay.panelOpacity; border.color:"#d78318"; border.width:1; clip:true
                    Rectangle { x:0; y:0; width:Math.max(3,5*gameOverlay.sizeFactor); height:parent.height; radius:3; color:"#d78318"; opacity:.88 }
                    Text { x:18*gameOverlay.sizeFactor; y:10*gameOverlay.sizeFactor; width:parent.width-36*gameOverlay.sizeFactor; text:"AI COMMS"; color:"#ffad42"; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(9,13*gameOverlay.sizeFactor) }
                    Rectangle { x:18*gameOverlay.sizeFactor; y:34*gameOverlay.sizeFactor; width:parent.width-36*gameOverlay.sizeFactor; height:1; color:"#8c571d"; opacity:.8 }
                    ListView {
                        id:overlayCommsList; x:18*gameOverlay.sizeFactor; y:42*gameOverlay.sizeFactor; width:parent.width-36*gameOverlay.sizeFactor; height:parent.height-54*gameOverlay.sizeFactor; clip:true; spacing:5*gameOverlay.sizeFactor; model:bridge.aiCommsRows
                        onCountChanged:if(count>0)positionViewAtEnd()
                        delegate:Item { required property var modelData; width:overlayCommsList.width; height:Math.max(28*gameOverlay.sizeFactor,overlayCommsText.implicitHeight+10*gameOverlay.sizeFactor); property bool commander:String(modelData.speaker||"").toUpperCase()==="CMDR"
                            Text { x:0;y:4*gameOverlay.sizeFactor;width:66*gameOverlay.sizeFactor;text:parent.commander?"CMDR":"BRIDGE";color:parent.commander?"#d9d4c2":"#ffad42";font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(8,11*gameOverlay.sizeFactor) }
                            Text { id:overlayCommsText;x:70*gameOverlay.sizeFactor;y:3*gameOverlay.sizeFactor;width:parent.width-70*gameOverlay.sizeFactor;text:String(modelData.text||"");color:"#e2ddce";font.family:"Consolas";font.pixelSize:Math.max(8,12*gameOverlay.sizeFactor);wrapMode:Text.WordWrap;maximumLineCount:gameOverlay.sideLayout?5:2;elide:Text.ElideRight }
                        }
                        Text { anchors.centerIn:parent;visible:overlayCommsList.count===0;text:"AI COMMS STANDING BY";color:"#8f897c";font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(8,12*gameOverlay.sizeFactor) }
                    }
                }
            }
        }
    }

    // DISPLAY: Bridge monitor, resolution and window-placement controls.
    Item {
        id: displayPage
        visible: root.currentPage === 9
        x: identity.x
        y: setupSectionTabs.y + setupSectionTabs.height + root.gap
        width: identity.width
        height: root.height - y - root.m

        MetalPanel {
            id: displayMainPanel
            anchors.fill: parent
            panelColor: root.screen
            SectionTitle { text:"DISPLAY / WINDOW CONTROL"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }

            Rectangle {
                x:28*root.scaleUnit; y:68*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:132*root.scaleUnit
                color:"#061008"; border.color:"#244a30"; border.width:1
                Text { text:"ACTIVE DISPLAY"; x:16*root.scaleUnit; y:12*root.scaleUnit; color:root.amber; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit) }
                Text { text:bridge.activeMonitorName; x:16*root.scaleUnit; y:42*root.scaleUnit; width:parent.width*.54; color:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(18,25*root.scaleUnit); elide:Text.ElideRight }
                Text { text:"RESOLUTION"; x:parent.width*.58; y:16*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,12*root.scaleUnit) }
                Text { text:bridge.activeMonitorResolution; x:parent.width*.58; y:42*root.scaleUnit; color:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(17,23*root.scaleUnit) }
                Text { text:"MONITORS // "+bridge.monitorCount+"    MODE // "+bridge.displayMode+"    WINDOWS SCALE // "+bridge.activeMonitorDpiScale+"    BRIDGE SCALE // "+root.layoutScalePercent+"%"; x:16*root.scaleUnit; y:92*root.scaleUnit; width:parent.width-32*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,13*root.scaleUnit); elide:Text.ElideRight }
            }

            Row {
                x:28*root.scaleUnit; y:224*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:92*root.scaleUnit; spacing:12*root.scaleUnit
                MechanicalButton { width:(parent.width-parent.spacing*3)/4; height:parent.height; text:"NEXT MONITOR"; subtext:"MOVE BRIDGE DISPLAY"; accent:root.green; labelScale:.72; onClicked:bridge.cycleMonitor() }
                MechanicalButton { width:(parent.width-parent.spacing*3)/4; height:parent.height; text:"MAXIMIZE"; subtext:"FIT ACTIVE DISPLAY"; accent:root.green; labelScale:.76; onClicked:bridge.maximizeBridge() }
                MechanicalButton { width:(parent.width-parent.spacing*3)/4; height:parent.height; text:"FULLSCREEN"; subtext:bridge.displayMode==="FULLSCREEN"?"ACTIVE":"TOGGLE WINDOW MODE"; accent:root.green; stateful:true; active:bridge.displayMode==="FULLSCREEN"; labelScale:.72; onClicked:bridge.toggleFullScreen() }
                MechanicalButton { width:(parent.width-parent.spacing*3)/4; height:parent.height; text:"RESET DISPLAY"; subtext:"PRIMARY MONITOR DEFAULT"; accent:root.red; labelScale:.68; onClicked:bridge.resetDisplaySettings() }
            }

            Rectangle {
                x:28*root.scaleUnit; y:342*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:452*root.scaleUnit
                color:"#050b07"; border.color:"#244a30"; border.width:1
                Text { text:"IN-GAME OVERLAY"; x:16*root.scaleUnit; y:12*root.scaleUnit; color:root.amber; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit) }
                Text { text:bridge.eliteOverlayCompatibility.indexOf("CAUTION")===0?"STATUS // FULLSCREEN INCOMPATIBLE":(bridge.eliteOverlayCompatibility.indexOf("READY")===0?"STATUS // READY // ELITE: BORDERLESS / WINDOWED":"STATUS // ELITE DISPLAY MODE UNKNOWN"); x:16*root.scaleUnit; y:38*root.scaleUnit; color:bridge.eliteOverlayCompatibility.indexOf("CAUTION")===0?root.red:(bridge.eliteOverlayCompatibility.indexOf("READY")===0?root.green:root.amber); font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,12*root.scaleUnit) }
                Rectangle { visible:bridge.eliteOverlayCompatibility.indexOf("CAUTION")===0; x:16*root.scaleUnit; y:62*root.scaleUnit; width:parent.width-32*root.scaleUnit; height:54*root.scaleUnit; color:"#24100c"; border.color:root.red; border.width:1
                    Text { anchors.centerIn:parent; width:parent.width-20*root.scaleUnit; text:"OVERLAY UNAVAILABLE // ELITE IS IN FULLSCREEN. CHANGE ELITE TO BORDERLESS OR WINDOWED MODE."; color:root.red; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(13,16*root.scaleUnit); horizontalAlignment:Text.AlignHCenter; wrapMode:Text.WordWrap }
                }
                Rectangle {
                    x:16*root.scaleUnit; y:(bridge.eliteOverlayCompatibility.indexOf("CAUTION")===0?124:110)*root.scaleUnit
                    width:parent.width-32*root.scaleUnit; height:58*root.scaleUnit
                    color:"#071009"; border.color:root.overlayRuntimeRequested?root.green:"#465047"; border.width:1
                    Text { text:"OVERLAY"; x:12*root.scaleUnit; y:7*root.scaleUnit; color:root.overlayRuntimeRequested?root.green:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,13*root.scaleUnit) }
                    Rectangle {
                        x:12*root.scaleUnit; y:29*root.scaleUnit; width:78*root.scaleUnit; height:22*root.scaleUnit; radius:11*root.scaleUnit
                        color:root.overlayRuntimeRequested?"#0c3923":"#181b18"; border.color:root.overlayRuntimeRequested?root.green:"#6d716c"; border.width:1
                        Text { anchors.centerIn:parent; text:root.overlayRuntimeRequested?"●  ON":"○  OFF"; color:root.overlayRuntimeRequested?root.green:"#aaa99f"; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(9,11*root.scaleUnit) }
                        MouseArea { anchors.fill:parent; onClicked:{
                            var v=!root.overlayRuntimeRequested
                            if(v && bridge.eliteOverlayCompatibility.indexOf("CAUTION")===0){ root.overlayRuntimeRequested=false; bridge.setGameOverlayEnabled(false); bridge.playUiCue("warning"); return }
                            root.overlayRuntimeRequested=v; bridge.setGameOverlayEnabled(v); bridge.playUiCue("confirm")
                        }}
                    }
                    Text { x:106*root.scaleUnit; y:32*root.scaleUnit; width:parent.width-122*root.scaleUnit; text:root.overlayRuntimeRequested?"CLICK-THROUGH // ELITE REMAINS FULLY INTERACTIVE":"IN-GAME OVERLAY DISABLED"; color:root.overlayRuntimeRequested?root.green:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(9,11*root.scaleUnit); elide:Text.ElideRight }
                }

                Text { text:"CONTENT"; x:18*root.scaleUnit; y:(bridge.eliteOverlayCompatibility.indexOf("CAUTION")===0?202:188)*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(9,11*root.scaleUnit) }
                Row { x:116*root.scaleUnit;y:(bridge.eliteOverlayCompatibility.indexOf("CAUTION")===0?192:178)*root.scaleUnit;width:parent.width-134*root.scaleUnit;height:52*root.scaleUnit;spacing:10*root.scaleUnit
                    OverlayChoice { width:(parent.width-parent.spacing*2)/3;height:parent.height;text:"ACTIVITY";selected:bridge.gameOverlayMode==="ACTIVITY";scaleUnit:root.scaleUnit;onClicked:bridge.setGameOverlayMode("ACTIVITY") }
                    OverlayChoice { width:(parent.width-parent.spacing*2)/3;height:parent.height;text:"HUD + CHAT";selected:bridge.gameOverlayMode==="ACTIVITY_CHAT";scaleUnit:root.scaleUnit;onClicked:bridge.setGameOverlayMode("ACTIVITY_CHAT") }
                    OverlayChoice { width:(parent.width-parent.spacing*2)/3;height:parent.height;text:"CHAT ONLY";selected:bridge.gameOverlayMode==="CHAT";scaleUnit:root.scaleUnit;onClicked:bridge.setGameOverlayMode("CHAT") }
                }
                Text { text:"POSITION";x:18*root.scaleUnit;y:240*root.scaleUnit;color:root.muted;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(9,11*root.scaleUnit) }
                Row { x:116*root.scaleUnit;y:230*root.scaleUnit;width:parent.width-134*root.scaleUnit;height:52*root.scaleUnit;spacing:10*root.scaleUnit
                    OverlayChoice { width:(parent.width-parent.spacing*2)/3;height:parent.height;text:"LEFT";selected:bridge.gameOverlayLayout==="LEFT";scaleUnit:root.scaleUnit;onClicked:{bridge.setGameOverlayLayout("LEFT");bridge.setGameOverlayPosition("LEFT")} }
                    OverlayChoice { width:(parent.width-parent.spacing*2)/3;height:parent.height;text:"TOP";selected:bridge.gameOverlayLayout==="TOP";scaleUnit:root.scaleUnit;onClicked:bridge.setGameOverlayLayout("TOP") }
                    OverlayChoice { width:(parent.width-parent.spacing*2)/3;height:parent.height;text:"RIGHT";selected:bridge.gameOverlayLayout==="RIGHT";scaleUnit:root.scaleUnit;onClicked:{bridge.setGameOverlayLayout("RIGHT");bridge.setGameOverlayPosition("RIGHT")} }
                }
                Text { text:"SIZE";x:18*root.scaleUnit;y:300*root.scaleUnit;color:root.muted;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(9,11*root.scaleUnit) }
                Row { x:116*root.scaleUnit;y:290*root.scaleUnit;width:parent.width-134*root.scaleUnit;height:52*root.scaleUnit;spacing:10*root.scaleUnit
                    OverlayChoice { width:(parent.width-parent.spacing*2)/3;height:parent.height;text:"SMALL";selected:bridge.gameOverlaySize==="SMALL";scaleUnit:root.scaleUnit;onClicked:bridge.setGameOverlaySize("SMALL") }
                    OverlayChoice { width:(parent.width-parent.spacing*2)/3;height:parent.height;text:"STANDARD";selected:bridge.gameOverlaySize==="STANDARD";scaleUnit:root.scaleUnit;onClicked:bridge.setGameOverlaySize("STANDARD") }
                    OverlayChoice { width:(parent.width-parent.spacing*2)/3;height:parent.height;text:"LARGE";selected:bridge.gameOverlaySize==="LARGE";scaleUnit:root.scaleUnit;onClicked:bridge.setGameOverlaySize("LARGE") }
                }
                Text { text:"TOP ALIGN";x:18*root.scaleUnit;y:360*root.scaleUnit;color:root.muted;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(9,11*root.scaleUnit);visible:bridge.gameOverlayLayout==="TOP" }
                Row { visible:bridge.gameOverlayLayout==="TOP";x:116*root.scaleUnit;y:350*root.scaleUnit;width:parent.width-134*root.scaleUnit;height:42*root.scaleUnit;spacing:8*root.scaleUnit
                    MechanicalButton { width:(parent.width-parent.spacing*2)/3;height:parent.height;text:"LEFT";active:bridge.gameOverlayPosition==="TOP_LEFT";stateful:true;accent:root.green;labelScale:.54;onClicked:bridge.setGameOverlayPosition("TOP_LEFT") }
                    MechanicalButton { width:(parent.width-parent.spacing*2)/3;height:parent.height;text:"CENTER";active:bridge.gameOverlayPosition==="TOP_CENTER";stateful:true;accent:root.green;labelScale:.54;onClicked:bridge.setGameOverlayPosition("TOP_CENTER") }
                    MechanicalButton { width:(parent.width-parent.spacing*2)/3;height:parent.height;text:"RIGHT";active:bridge.gameOverlayPosition==="TOP_RIGHT";stateful:true;accent:root.green;labelScale:.54;onClicked:bridge.setGameOverlayPosition("TOP_RIGHT") }
                }
                Text { text:"TRANSPARENCY";x:18*root.scaleUnit;y:340*root.scaleUnit;color:root.muted;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(9,11*root.scaleUnit) }
                Text { text:bridge.gameOverlayOpacity+"% VISIBLE";x:parent.width-130*root.scaleUnit;y:340*root.scaleUnit;width:112*root.scaleUnit;color:root.green;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(9,11*root.scaleUnit);horizontalAlignment:Text.AlignRight }
                Slider { id:overlayOpacitySlider;x:18*root.scaleUnit;y:362*root.scaleUnit;width:parent.width-36*root.scaleUnit;from:25;to:100;stepSize:1;value:bridge.gameOverlayOpacity;onPressedChanged:if(!pressed)bridge.setGameOverlayOpacity(Math.round(value)) }
                Text { text:"DEFAULT // HUD + CHAT  •  RIGHT  •  STANDARD  •  75%";x:18*root.scaleUnit;y:408*root.scaleUnit;width:parent.width-36*root.scaleUnit;color:root.whiteText;font.family:"Consolas";font.pixelSize:Math.max(9,10*root.scaleUnit);elide:Text.ElideRight }
            }

            Rectangle {
                x:28*root.scaleUnit; y:834*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:132*root.scaleUnit
                color:"#071009"; border.color:"#3b493f"; border.width:1
                Text { text:"DISPLAY SCALE STATUS"; x:16*root.scaleUnit; y:14*root.scaleUnit; color:root.amber; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,13*root.scaleUnit) }
                Text { text:"MONITOR // "+bridge.activeMonitorResolution+"    WINDOWS SCALE // "+bridge.activeMonitorDpiScale; x:16*root.scaleUnit; y:44*root.scaleUnit; width:parent.width-32*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,13*root.scaleUnit); elide:Text.ElideRight }
                Text { text:"WINDOWS AREA // "+bridge.activeMonitorLogicalResolution+"    CURRENT WINDOW // "+Math.round(root.width)+" × "+Math.round(root.height)+"    BRIDGE SCALE // "+root.layoutScalePercent+"%"; x:16*root.scaleUnit; y:73*root.scaleUnit; width:parent.width-32*root.scaleUnit; color:root.green; font.family:"Consolas"; font.pixelSize:Math.max(10,13*root.scaleUnit); elide:Text.ElideRight }
                Text { text:"Resolution and Windows scaling are detected automatically. No per-monitor setup is required."; x:16*root.scaleUnit; y:102*root.scaleUnit; width:parent.width-32*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,12*root.scaleUnit); elide:Text.ElideRight }
            }
        }
    }


    // SETUP MODULE: universal categorized configuration hub.
    // Specialist pages and Setup share the same backend settings. Elite own
    // .binds file is scanned/read-only; Bridge-owned HOTAS mappings are managed here.
    Item {
        id: setupPage
        visible: root.currentPage === 8
        x: identity.x
        y: setupSectionTabs.y + setupSectionTabs.height + root.gap
        width: identity.width
        height: root.height - y - root.m
        property string homeDraft: ""
        property string bookmark1Draft: ""
        property string bookmark2Draft: ""
        property string apiKeyDraft: ""
        property string commanderDraft: ""
        property string aiContextDraft: ""
        property string selectedControlAction: "push_to_talk"
        property int selectedControlRow: -1
        property string selectedControlLabel: "PUSH TO TALK [REQUIRED]"
        property bool controlSelectionTouched: false
        property bool systemCheckVisible: false
        property bool systemCheckRunning: false
        property string selectedControlColumn: ""
        readonly property bool keyboardCaptureActive: bridge.keyboardCaptureActive
        readonly property bool controlCaptureActive: String(bridge.controlCaptureAction || "") !== ""
        property string lastHome: ""
        property string lastBookmark1: ""
        property string lastBookmark2: ""
        property string lastCommander: ""
        property string lastAiContext: ""

        Component.onCompleted: {
            homeDraft=bridge.navHomeSystem; bookmark1Draft=bridge.navBookmark1System; bookmark2Draft=bridge.navBookmark2System
            commanderDraft=bridge.setupCommanderAddress
            aiContextDraft=bridge.setupAiContext
            lastHome=bridge.navHomeSystem; lastBookmark1=bridge.navBookmark1System; lastBookmark2=bridge.navBookmark2System; lastCommander=bridge.setupCommanderAddress; lastAiContext=bridge.setupAiContext
        }
        Connections { target:bridge; function onStateChanged() {
            if (bridge.navHomeSystem!==setupPage.lastHome) { setupPage.lastHome=bridge.navHomeSystem; if(!setupHomeInput.activeFocus) setupPage.homeDraft=bridge.navHomeSystem }
            if (bridge.navBookmark1System!==setupPage.lastBookmark1) { setupPage.lastBookmark1=bridge.navBookmark1System; if(!setupBookmark1Input.activeFocus) setupPage.bookmark1Draft=bridge.navBookmark1System }
            if (bridge.navBookmark2System!==setupPage.lastBookmark2) { setupPage.lastBookmark2=bridge.navBookmark2System; if(!setupBookmark2Input.activeFocus) setupPage.bookmark2Draft=bridge.navBookmark2System }
            if (bridge.setupCommanderAddress!==setupPage.lastCommander) { setupPage.lastCommander=bridge.setupCommanderAddress; if(!setupCommanderInput.activeFocus) setupPage.commanderDraft=bridge.setupCommanderAddress }
            if (bridge.setupAiContext!==setupPage.lastAiContext) { setupPage.lastAiContext=bridge.setupAiContext; if(!setupAiContextInput.activeFocus) setupPage.aiContextDraft=bridge.setupAiContext }
        } }

        Timer {
            id:systemCheckFinishTimer
            interval:1400
            repeat:false
            onTriggered:{setupPage.systemCheckRunning=false;bridge.playUiCue(bridge.setupReady&&!bridge.setupLimited?"confirm":"warn")}
        }

        Flickable {
            id:setupScroll; anchors.fill:parent; clip:true; contentWidth:width; contentHeight:setupColumn.height+180*root.scaleUnit
            boundsBehavior:Flickable.StopAtBounds; ScrollBar.vertical:ScrollBar { policy:ScrollBar.AlwaysOn }
            Column {
                id:setupColumn; width:setupScroll.width-22*root.scaleUnit; spacing:28*root.scaleUnit

                MetalPanel {
                    width:parent.width; height:setupPage.systemCheckVisible?760*root.scaleUnit:210*root.scaleUnit; panelColor:root.screen
                    SectionTitle { text:"SYSTEM CHECK // ON DEMAND"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }
                    Text {
                        x:28*root.scaleUnit; y:66*root.scaleUnit; width:parent.width-430*root.scaleUnit; height:76*root.scaleUnit
                        text:"Bridge starts normally. Run this check whenever you want a quick diagnostic of Elite connectivity, required controls, PTT, audio, AI and controller health."
                        color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(11,14*root.scaleUnit); wrapMode:Text.WordWrap
                    }
                    MechanicalButton {
                        x:parent.width-382*root.scaleUnit; y:58*root.scaleUnit; width:354*root.scaleUnit; height:96*root.scaleUnit
                        text:"RUN SYSTEM CHECK"; subtext:"OPTIONAL DIAGNOSTIC // NO STARTUP GATE"; accent:root.green; labelScale:.67
                        onClicked:{
                            setupPage.systemCheckVisible=true
                            setupPage.systemCheckRunning=true
                            bridge.playUiCue("nav")
                            bridge.requestCommand("setup_preflight")
                            bridge.requestCommand("setup_binds")
                            bridge.requestCommand("audio_rescan")
                            systemCheckFinishTimer.restart()
                        }
                    }
                    Text {
                        visible:!setupPage.systemCheckVisible
                        x:28*root.scaleUnit; y:148*root.scaleUnit; width:parent.width-56*root.scaleUnit
                        text:"Nothing runs automatically. Healthy systems stay out of your way."
                        color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,12*root.scaleUnit)
                    }

                    Rectangle {
                        visible:setupPage.systemCheckVisible
                        x:28*root.scaleUnit; y:178*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:74*root.scaleUnit
                        color:"#061008"
                        border.color:setupPage.systemCheckRunning?root.amber:(bridge.setupReady&&!bridge.setupLimited?root.green:root.amber); border.width:2
                        Text {
                            x:16*root.scaleUnit; y:9*root.scaleUnit; width:parent.width-32*root.scaleUnit
                            text:setupPage.systemCheckRunning?"SYSTEM CHECK RUNNING...":(bridge.setupReady&&!bridge.setupLimited?"ALL SYSTEMS NOMINAL // BRIDGE READY":"SYSTEM CHECK COMPLETE // ATTENTION ITEMS FOUND")
                            color:setupPage.systemCheckRunning?root.amber:(bridge.setupReady&&!bridge.setupLimited?root.green:root.amber)
                            font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(14,19*root.scaleUnit)
                        }
                        Text {
                            x:16*root.scaleUnit; y:42*root.scaleUnit; width:parent.width-32*root.scaleUnit
                            text:setupPage.systemCheckRunning?"SCANNING BRIDGE / ELITE / CONTROLS / AUDIO":(bridge.setupReady&&!bridge.setupLimited?"No action required.":"Review the highlighted item below. Open its settings only if you want to correct it.")
                            color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(10,12*root.scaleUnit); elide:Text.ElideRight
                        }
                    }

                    Grid {
                        visible:setupPage.systemCheckVisible
                        x:28*root.scaleUnit; y:270*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:300*root.scaleUnit
                        columns:2; columnSpacing:14*root.scaleUnit; rowSpacing:8*root.scaleUnit
                        Repeater { model:root.startupPreflightRows()
                            Rectangle {
                                width:(parent.width-parent.columnSpacing)/2; height:58*root.scaleUnit
                                property string stat:String(modelData.status||"INFO").toUpperCase()
                                property bool good:stat==="READY"
                                property bool bad:stat==="MISSING"||stat==="ERROR"
                                color:bad?"#170807":"#050b07"; border.color:good?"#1b6036":(bad?root.red:(stat==="NEEDS ATTENTION"?root.amber:"#34433b")); border.width:bad?2:1
                                Text{text:modelData.label;x:10*root.scaleUnit;y:7*root.scaleUnit;width:parent.width*.55;color:root.muted;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(10,12*root.scaleUnit);elide:Text.ElideRight}
                                Text{text:parent.stat;anchors.right:parent.right;anchors.rightMargin:10*root.scaleUnit;y:7*root.scaleUnit;color:parent.good?root.green:(parent.bad?root.red:(parent.stat==="NEEDS ATTENTION"?root.amber:root.whiteText));font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(10,12*root.scaleUnit)}
                                Text{text:modelData.detail;x:10*root.scaleUnit;y:29*root.scaleUnit;width:parent.width-20*root.scaleUnit;color:root.whiteText;font.family:"Consolas";font.pixelSize:Math.max(9,10*root.scaleUnit);elide:Text.ElideRight}
                            }
                        }
                    }
                    Row {
                        visible:setupPage.systemCheckVisible
                        x:28*root.scaleUnit; y:600*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:82*root.scaleUnit; spacing:12*root.scaleUnit
                        MechanicalButton { width:(parent.width-parent.spacing*2)/3; height:parent.height; text:"CONTROLS"; subtext:"BINDINGS / PTT"; accent:root.green; labelScale:.72; onClicked:{root.currentPage=10;bridge.playUiCue("nav")} }
                        MechanicalButton { width:(parent.width-parent.spacing*2)/3; height:parent.height; text:"AI + VOICE"; subtext:"API / MICROPHONE"; accent:root.green; labelScale:.72; onClicked:{root.currentPage=6;bridge.playUiCue("nav")} }
                        MechanicalButton { width:(parent.width-parent.spacing*2)/3; height:parent.height; text:"AUDIO"; subtext:"OUTPUT / DEVICES"; accent:root.green; labelScale:.72; onClicked:{root.currentPage=7;bridge.playUiCue("nav")} }
                    }
                }

                MetalPanel { width:parent.width; height:300*root.scaleUnit; panelColor:root.screen
                    SectionTitle { text:"COMMANDER IDENTITY"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }
                    Text { text:"BRIDGE CALLS ME"; x:28*root.scaleUnit; y:70*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit) }
                    Rectangle { x:28*root.scaleUnit; y:98*root.scaleUnit; width:parent.width-340*root.scaleUnit; height:64*root.scaleUnit; color:"#061008"; border.color:setupCommanderInput.activeFocus?root.green:"#244a30"; border.width:1
                        TextInput { id:setupCommanderInput; text:setupPage.commanderDraft; anchors.fill:parent; anchors.margins:10*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(13,16*root.scaleUnit); verticalAlignment:TextInput.AlignVCenter; selectByMouse:true; onTextEdited:setupPage.commanderDraft=text; Keys.onReturnPressed:bridge.setSetupValue("commander_address",setupPage.commanderDraft) }
                    }
                    MechanicalButton { x:parent.width-298*root.scaleUnit; y:98*root.scaleUnit; width:270*root.scaleUnit; height:64*root.scaleUnit; text:"SAVE CALL NAME"; subtext:"BRIDGE VOICE ADDRESS"; accent:root.green; labelScale:.70; onClicked:bridge.setSetupValue("commander_address",setupPage.commanderDraft) }
                    Text { text:"AI Co-Pilot connection and API setup now live under AI & VOICE. System settings no longer expose the API key."; x:28*root.scaleUnit; y:188*root.scaleUnit; width:parent.width-56*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,12*root.scaleUnit); wrapMode:Text.WordWrap }
                }

                
                
                
                
                
                MetalPanel { width:parent.width; height:1430*root.scaleUnit; panelColor:root.screen
                    SectionTitle { text:"AI + AUTOMATION"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }
                    Text{text:"AI BEHAVIOR";x:28*root.scaleUnit;y:64*root.scaleUnit;color:root.amber;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(11,14*root.scaleUnit)}
                    Row{x:28*root.scaleUnit;y:90*root.scaleUnit;width:parent.width-56*root.scaleUnit;height:92*root.scaleUnit;spacing:10*root.scaleUnit
                        MechanicalButton{width:(parent.width-parent.spacing*2)/3;height:parent.height;text:"SUGGEST ONLY";subtext:"ADVICE // NO ACTION";stateful:true;active:bridge.aiToolMode==="Suggest Only";accent:root.green;labelScale:.62;onClicked:bridge.setSetupValue("ai_tool_mode","Suggest Only")}
                        MechanicalButton{width:(parent.width-parent.spacing*2)/3;height:parent.height;text:"ASK BEFORE ACTING";subtext:"APPROVAL REQUIRED";stateful:true;active:bridge.aiToolMode==="Ask Before Acting";accent:root.green;labelScale:.58;onClicked:bridge.setSetupValue("ai_tool_mode","Ask Before Acting")}
                        MechanicalButton{width:(parent.width-parent.spacing*2)/3;height:parent.height;text:"AUTO NAVIGATION";subtext:"ALLOWED AUTO ACTIONS";stateful:true;active:bridge.aiToolMode==="Auto Navigation";accent:root.green;labelScale:.60;onClicked:bridge.setSetupValue("ai_tool_mode","Auto Navigation")}
                    }
                    FlipSwitch{x:28*root.scaleUnit;y:194*root.scaleUnit;width:parent.width-56*root.scaleUnit;height:82*root.scaleUnit;scaleUnit:root.scaleUnit;text:"AUTOMATIC AI ASSISTANCE";subtext:checked?"BACKGROUND EVENT ADVISOR ENABLED":"OFF // MANUAL AI STILL AVAILABLE";checked:bridge.aiSmartAutoEnabled;accent:root.green;onToggled:function(requestedChecked){bridge.setSetupBool("ai_smart_auto",requestedChecked)}}
                    Text{text:"ACTION MODE controls whether AI actions are automatic, require approval, or are suggestions only. Smart Auto lets selected game events request AI analysis/commentary.";x:28*root.scaleUnit;y:286*root.scaleUnit;width:parent.width-56*root.scaleUnit;color:root.muted;font.family:"Consolas";font.pixelSize:Math.max(10,12*root.scaleUnit);wrapMode:Text.WordWrap}

                    Text{text:"AI EVENT TRIGGERS";x:28*root.scaleUnit;y:340*root.scaleUnit;color:root.amber;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(11,14*root.scaleUnit)}
                    Row{x:28*root.scaleUnit;y:404*root.scaleUnit;width:parent.width-56*root.scaleUnit;height:88*root.scaleUnit;spacing:12*root.scaleUnit
                        FlipSwitch{width:(parent.width-parent.spacing*2)/3;height:parent.height;scaleUnit:root.scaleUnit;text:"TRADE + POWERPLAY";subtext:checked?"AUTO COMMENTARY ON":"OFF";checked:bridge.setupAiTradeAuto;accent:root.green;onToggled:function(requestedChecked){bridge.setSetupBool("ai_trade_auto",requestedChecked)}}
                        FlipSwitch{width:(parent.width-parent.spacing*2)/3;height:parent.height;scaleUnit:root.scaleUnit;text:"MISSIONS";subtext:checked?"AUTO COMMENTARY ON":"OFF";checked:bridge.setupAiMissionAuto;accent:root.green;onToggled:function(requestedChecked){bridge.setSetupBool("ai_mission_auto",requestedChecked)}}
                        FlipSwitch{width:(parent.width-parent.spacing*2)/3;height:parent.height;scaleUnit:root.scaleUnit;text:"TRAVEL + DOCKING";subtext:checked?"AUTO COMMENTARY ON":"OFF";checked:bridge.setupAiTravelAuto;accent:root.green;onToggled:function(requestedChecked){bridge.setSetupBool("ai_travel_auto",requestedChecked)}}
                    }
                    Text{text:"These switches decide which event families may automatically ask the AI for commentary/advice. They do not directly fly the ship.";x:28*root.scaleUnit;y:366*root.scaleUnit;width:parent.width-56*root.scaleUnit;color:root.muted;font.family:"Consolas";font.pixelSize:Math.max(10,12*root.scaleUnit);wrapMode:Text.WordWrap}

                    Text{text:"STATION MAINTENANCE";x:28*root.scaleUnit;y:520*root.scaleUnit;color:root.amber;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(11,14*root.scaleUnit)}
                    Row{x:28*root.scaleUnit;y:580*root.scaleUnit;width:parent.width-56*root.scaleUnit;height:88*root.scaleUnit;spacing:12*root.scaleUnit
                        FlipSwitch{width:(parent.width-parent.spacing*2)/3;height:parent.height;scaleUnit:root.scaleUnit;text:"AUTO REFUEL";subtext:checked?"ATTEMPT ONCE AFTER DOCK":"OFF";checked:bridge.setupAutoRefuel;accent:root.green;onToggled:function(requestedChecked){bridge.setSetupBool("auto_refuel",requestedChecked)}}
                        FlipSwitch{width:(parent.width-parent.spacing*2)/3;height:parent.height;scaleUnit:root.scaleUnit;text:"AUTO REPAIR";subtext:checked?"REPAIR ALL AFTER DOCK":"OFF";checked:bridge.setupAutoRepair;accent:root.green;onToggled:function(requestedChecked){bridge.setSetupBool("auto_repair",requestedChecked)}}
                        FlipSwitch{width:(parent.width-parent.spacing*2)/3;height:parent.height;scaleUnit:root.scaleUnit;text:"AUTO REARM";subtext:checked?"REARM AFTER DOCK":"OFF";checked:bridge.setupAutoRearm;accent:root.green;onToggled:function(requestedChecked){bridge.setSetupBool("auto_rearm",requestedChecked)}}
                    }
                    Text{text:"Auto services run after docking when the station offers that service. They are persistent preferences.";x:28*root.scaleUnit;y:546*root.scaleUnit;width:parent.width-56*root.scaleUnit;color:root.muted;font.family:"Consolas";font.pixelSize:Math.max(10,12*root.scaleUnit);wrapMode:Text.WordWrap}

                    Text{text:"COMBAT ASSIST";x:28*root.scaleUnit;y:700*root.scaleUnit;color:root.amber;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(11,14*root.scaleUnit)}
                    Row{x:28*root.scaleUnit;y:772*root.scaleUnit;width:parent.width-56*root.scaleUnit;height:88*root.scaleUnit;spacing:12*root.scaleUnit
                        FlipSwitch{width:(parent.width-parent.spacing*2)/3;height:parent.height;scaleUnit:root.scaleUnit;text:"DYNAMIC PIPS";subtext:checked?"AUTO POWER DISTRIBUTION":"OFF";checked:bridge.setupDynamicPips;accent:root.green;onToggled:function(requestedChecked){bridge.setSetupBool("dynamic_pips",requestedChecked)}}
                        FlipSwitch{width:(parent.width-parent.spacing*2)/3;height:parent.height;scaleUnit:root.scaleUnit;text:"AUTO POWER PLANT";subtext:checked?"HEAVY WANTED TARGETS":"OFF";checked:bridge.setupAutoPowerPlant;accent:root.green;onToggled:function(requestedChecked){bridge.setSetupBool("auto_powerplant",requestedChecked)}}
                        FlipSwitch{width:(parent.width-parent.spacing*2)/3;height:parent.height;scaleUnit:root.scaleUnit;text:"AUTO CHAFF";subtext:checked?("PROFILE // "+bridge.setupAutoChaffProfile):"OFF";checked:bridge.setupAutoChaff;accent:root.green;onToggled:function(requestedChecked){bridge.setSetupBool("auto_chaff",requestedChecked)}}
                    }
                    Text{text:"Dynamic PIPs automatically changes SYS/ENG/WEP distribution from live combat context, then recovers afterward. Auto Power Plant selects the Power Plant subsystem only on fully scanned WANTED heavy ships. Auto Chaff reacts to sustained incoming-fire pressure in normal-space combat.";x:28*root.scaleUnit;y:726*root.scaleUnit;width:parent.width-56*root.scaleUnit;color:root.muted;font.family:"Consolas";font.pixelSize:Math.max(10,12*root.scaleUnit);wrapMode:Text.WordWrap}

                    Text{text:"AUTO CHAFF PROFILE";x:28*root.scaleUnit;y:892*root.scaleUnit;color:root.muted;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(11,14*root.scaleUnit)}
                    Row{x:28*root.scaleUnit;y:920*root.scaleUnit;width:parent.width-56*root.scaleUnit;height:92*root.scaleUnit;spacing:10*root.scaleUnit
                        MechanicalButton{width:(parent.width-parent.spacing*2)/3;height:parent.height;text:"LOW";subtext:"CONSERVATIVE";stateful:true;active:bridge.setupAutoChaffProfile==="LOW";accent:root.green;labelScale:.72;onClicked:bridge.setSetupValue("auto_chaff_profile","LOW")}
                        MechanicalButton{width:(parent.width-parent.spacing*2)/3;height:parent.height;text:"MED";subtext:"BALANCED // DEFAULT";stateful:true;active:bridge.setupAutoChaffProfile==="MED";accent:root.green;labelScale:.72;onClicked:bridge.setSetupValue("auto_chaff_profile","MED")}
                        MechanicalButton{width:(parent.width-parent.spacing*2)/3;height:parent.height;text:"HIGH";subtext:"AGGRESSIVE";stateful:true;active:bridge.setupAutoChaffProfile==="HIGH";accent:root.green;labelScale:.72;onClicked:bridge.setSetupValue("auto_chaff_profile","HIGH")}
                    }
                    Text{text:bridge.setupAutoChaffProfile==="LOW"?"LOW // CONSERVATIVE: waits 45 sec of combat, needs 2 incoming-fire warnings within 90 sec, then 35 sec cooldown.":(bridge.setupAutoChaffProfile==="HIGH"?"HIGH // AGGRESSIVE: waits 10 sec, needs 1 incoming-fire warning within 30 sec, then 15 sec cooldown.":"MED // BALANCED: waits 25 sec, needs 1 incoming-fire warning within 45 sec, then 25 sec cooldown.");x:28*root.scaleUnit;y:1020*root.scaleUnit;width:parent.width-56*root.scaleUnit;height:54*root.scaleUnit;color:root.whiteText;font.family:"Consolas";font.pixelSize:Math.max(10,12*root.scaleUnit);wrapMode:Text.WordWrap;verticalAlignment:Text.AlignVCenter;horizontalAlignment:Text.AlignHCenter}

                    Text{text:"SESSION TRAVEL";x:28*root.scaleUnit;y:1100*root.scaleUnit;color:root.amber;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(11,14*root.scaleUnit)}
                    FlipSwitch{x:28*root.scaleUnit;y:1128*root.scaleUnit;width:parent.width-56*root.scaleUnit;height:88*root.scaleUnit;scaleUnit:root.scaleUnit;text:"CLEAR + JUMP AFTER LAUNCH";subtext:checked?"SESSION RULE ACTIVE":"SESSION RULE OFF";checked:bridge.aiLaunchRuleEnabled;accent:root.green;onToggled:bridge.requestCommand("ai_toggle_launch_rule")}
                    Text{text:"Session-only rule: after Bridge Auto Launch clears the station, allow the automation flow to continue into the plotted jump. It resets when Bridge exits.";x:28*root.scaleUnit;y:1226*root.scaleUnit;width:parent.width-56*root.scaleUnit;color:root.muted;font.family:"Consolas";font.pixelSize:Math.max(10,12*root.scaleUnit);wrapMode:Text.WordWrap}
                }

                MetalPanel { width:parent.width; height:540*root.scaleUnit; panelColor:root.screen
                    SectionTitle { text:"NAVIGATION MEMORIES"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }
                    Text{text:"HOME / BOOKMARKS ARE SHARED WITH NAVIGATION, COLONIZATION AND VOICE COMMANDS.";x:28*root.scaleUnit;y:58*root.scaleUnit;width:parent.width-56*root.scaleUnit;color:root.muted;font.family:"Consolas";font.pixelSize:Math.max(10,12*root.scaleUnit)}
                    Column { x:28*root.scaleUnit; y:92*root.scaleUnit; width:parent.width-56*root.scaleUnit; spacing:18*root.scaleUnit
                        Item { width:parent.width; height:88*root.scaleUnit; Text{text:"HOME";color:root.green;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(12,15*root.scaleUnit)} Rectangle{x:0;y:28*root.scaleUnit;width:parent.width-300*root.scaleUnit;height:64*root.scaleUnit;color:"#061008";border.color:setupHomeInput.activeFocus?root.green:"#244a30";border.width:1;TextInput{id:setupHomeInput;text:setupPage.homeDraft;anchors.fill:parent;anchors.margins:10*root.scaleUnit;color:root.whiteText;font.family:"Consolas";font.pixelSize:Math.max(13,16*root.scaleUnit);verticalAlignment:TextInput.AlignVCenter;selectByMouse:true;onTextEdited:setupPage.homeDraft=text;Keys.onReturnPressed:bridge.setNavigationMemory("home",setupPage.homeDraft)}} MechanicalButton{anchors.right:parent.right;y:28*root.scaleUnit;width:280*root.scaleUnit;height:64*root.scaleUnit;text:"SAVE HOME";subtext:"NAV MEMORY";accent:root.green;labelScale:.80;onClicked:bridge.setNavigationMemory("home",setupPage.homeDraft)} }
                        Item { width:parent.width; height:88*root.scaleUnit; Text{text:"BOOKMARK 1";color:root.whiteText;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(12,15*root.scaleUnit)} Rectangle{x:0;y:28*root.scaleUnit;width:parent.width-300*root.scaleUnit;height:64*root.scaleUnit;color:"#061008";border.color:setupBookmark1Input.activeFocus?root.green:"#244a30";border.width:1;TextInput{id:setupBookmark1Input;text:setupPage.bookmark1Draft;anchors.fill:parent;anchors.margins:10*root.scaleUnit;color:root.whiteText;font.family:"Consolas";font.pixelSize:Math.max(13,16*root.scaleUnit);verticalAlignment:TextInput.AlignVCenter;selectByMouse:true;onTextEdited:setupPage.bookmark1Draft=text;Keys.onReturnPressed:bridge.setNavigationMemory("bookmark1",setupPage.bookmark1Draft)}} MechanicalButton{anchors.right:parent.right;y:28*root.scaleUnit;width:280*root.scaleUnit;height:64*root.scaleUnit;text:"SAVE BOOKMARK 1";subtext:"NAV MEMORY";accent:root.green;labelScale:.68;onClicked:bridge.setNavigationMemory("bookmark1",setupPage.bookmark1Draft)} }
                        Item { width:parent.width; height:88*root.scaleUnit; Text{text:"BOOKMARK 2";color:root.whiteText;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(12,15*root.scaleUnit)} Rectangle{x:0;y:28*root.scaleUnit;width:parent.width-300*root.scaleUnit;height:64*root.scaleUnit;color:"#061008";border.color:setupBookmark2Input.activeFocus?root.green:"#244a30";border.width:1;TextInput{id:setupBookmark2Input;text:setupPage.bookmark2Draft;anchors.fill:parent;anchors.margins:10*root.scaleUnit;color:root.whiteText;font.family:"Consolas";font.pixelSize:Math.max(13,16*root.scaleUnit);verticalAlignment:TextInput.AlignVCenter;selectByMouse:true;onTextEdited:setupPage.bookmark2Draft=text;Keys.onReturnPressed:bridge.setNavigationMemory("bookmark2",setupPage.bookmark2Draft)}} MechanicalButton{anchors.right:parent.right;y:28*root.scaleUnit;width:280*root.scaleUnit;height:64*root.scaleUnit;text:"SAVE BOOKMARK 2";subtext:"NAV MEMORY";accent:root.green;labelScale:.68;onClicked:bridge.setNavigationMemory("bookmark2",setupPage.bookmark2Draft)} }
                    }
                }

                MetalPanel { width:parent.width; height:830*root.scaleUnit; panelColor:root.screen
                    SectionTitle { text:"USAGE + MAINTENANCE"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }
                    Rectangle { x:28*root.scaleUnit; y:68*root.scaleUnit; width:parent.width*.62; height:220*root.scaleUnit; color:"#050b07"; border.color:"#244a30"; border.width:1
                        Text{text:"CUMULATIVE AI USAGE // PERSISTS ACROSS RESTARTS";x:14*root.scaleUnit;y:12*root.scaleUnit;color:root.muted;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(10,13*root.scaleUnit)}
                        Text{text:"AI REQUESTS";x:16*root.scaleUnit;y:52*root.scaleUnit;color:root.muted;font.family:"Consolas";font.pixelSize:Math.max(11,14*root.scaleUnit)} Text{text:bridge.aiUsageCalls+"";anchors.right:parent.right;anchors.rightMargin:16*root.scaleUnit;y:52*root.scaleUnit;color:root.green;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(12,15*root.scaleUnit)}
                        Text{text:"INPUT TOKENS";x:16*root.scaleUnit;y:86*root.scaleUnit;color:root.muted;font.family:"Consolas";font.pixelSize:Math.max(11,14*root.scaleUnit)} Text{text:root.fmtNumber(bridge.aiUsageInputTokens);anchors.right:parent.right;anchors.rightMargin:16*root.scaleUnit;y:86*root.scaleUnit;color:root.green;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(12,15*root.scaleUnit)}
                        Text{text:"OUTPUT TOKENS";x:16*root.scaleUnit;y:120*root.scaleUnit;color:root.muted;font.family:"Consolas";font.pixelSize:Math.max(11,14*root.scaleUnit)} Text{text:root.fmtNumber(bridge.aiUsageOutputTokens);anchors.right:parent.right;anchors.rightMargin:16*root.scaleUnit;y:120*root.scaleUnit;color:root.green;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(12,15*root.scaleUnit)}
                        Text{text:"EST. LLM COST";x:16*root.scaleUnit;y:154*root.scaleUnit;color:root.muted;font.family:"Consolas";font.pixelSize:Math.max(11,14*root.scaleUnit)} Text{text:bridge.aiUsageEstimatedCostText;anchors.right:parent.right;anchors.rightMargin:16*root.scaleUnit;y:154*root.scaleUnit;color:root.green;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(12,15*root.scaleUnit)}
                        Text{text:"TRANSCRIBED AUDIO";x:16*root.scaleUnit;y:188*root.scaleUnit;color:root.muted;font.family:"Consolas";font.pixelSize:Math.max(11,14*root.scaleUnit)} Text{text:bridge.aiUsageTranscriptionSecondsText;anchors.right:parent.right;anchors.rightMargin:16*root.scaleUnit;y:188*root.scaleUnit;color:root.green;font.family:"Consolas";font.bold:true;font.pixelSize:Math.max(12,15*root.scaleUnit)}
                    }
                    MechanicalButton { x:parent.width*.66; y:86*root.scaleUnit; width:parent.width*.31; height:94*root.scaleUnit; text:"RESET USAGE COUNTER"; subtext:"USAGE TOTALS ONLY"; accent:root.red; danger:true; labelScale:.72; onClicked:bridge.requestCommand("ai_usage_reset") }
                    Rectangle { x:parent.width*.66; y:196*root.scaleUnit; width:parent.width*.31; height:92*root.scaleUnit; color:"#050b07"; border.color:"#3c493b"; border.width:1
                        Text { text:"RESETS REQUEST / TOKEN / COST / TRANSCRIPTION COUNTERS ONLY. IT DOES NOT CLEAR THE API KEY OR CHANGE ANY SETTING."; anchors.centerIn:parent; width:parent.width-24*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(10,12*root.scaleUnit); wrapMode:Text.WordWrap; horizontalAlignment:Text.AlignHCenter }
                    }
                    Rectangle { x:28*root.scaleUnit; y:326*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:350*root.scaleUnit; color:"#050b07"; border.color:"#244a30"; border.width:1
                        Text { text:"SETUP + TUTORIAL"; x:16*root.scaleUnit; y:14*root.scaleUnit; color:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(12,15*root.scaleUnit) }
                        Text { text:"Reopen setup choices or run the optional full tutorial."; x:16*root.scaleUnit; y:44*root.scaleUnit; width:parent.width-32*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(10,12*root.scaleUnit); wrapMode:Text.WordWrap }
                        Row { x:16*root.scaleUnit; y:92*root.scaleUnit; width:parent.width-32*root.scaleUnit; height:86*root.scaleUnit; spacing:14*root.scaleUnit
                            MechanicalButton {
                                width:(parent.width-parent.spacing)/2; height:parent.height
                                text:"RUN SETUP WIZARD"
                                subtext:"START FROM CHOOSE MODE"
                                accent:root.green; labelScale:.66
                                onClicked:root.openFullSetupWizard()
                            }
                            FlipSwitch { width:(parent.width-parent.spacing)/2; height:parent.height; scaleUnit:root.scaleUnit; text:"SHOW AT STARTUP"; subtext:checked?"WIZARD WILL OPEN NEXT LAUNCH":"WIZARD HIDDEN AT STARTUP"; checked:bridge.firstRunSetupEnabled; accent:root.green; onToggled:function(requestedChecked){root.introSessionDismissed=true;bridge.setFirstRunSetupEnabled(requestedChecked);bridge.playUiCue(requestedChecked?"confirm":"nav")} }
                        }
                        Text { text:"FULL TUTORIAL"; x:16*root.scaleUnit; y:196*root.scaleUnit; color:root.amber; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,13*root.scaleUnit) }
                        Row { x:16*root.scaleUnit; y:224*root.scaleUnit; width:parent.width-32*root.scaleUnit; height:92*root.scaleUnit; spacing:14*root.scaleUnit
                            MechanicalButton { width:(parent.width-parent.spacing)/2; height:parent.height; text:"START TUTORIAL"; subtext:"OPTIONAL FULL GUIDED TOUR"; accent:root.amber; labelScale:.63; onClicked:{root.launchLiveOrientation(true);bridge.playUiCue("confirm")} }
                            Rectangle { width:(parent.width-parent.spacing)/2; height:parent.height; color:"#050b07"; border.color:"#3c493b"; border.width:1
                                Text { anchors.fill:parent; anchors.margins:14*root.scaleUnit; text:"The tutorial never starts by itself. Run it whenever you want a complete guided tour of the Bridge."; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(12,16*root.scaleUnit); lineHeight:1.18; wrapMode:Text.WordWrap; verticalAlignment:Text.AlignVCenter }
                            }
                        }
                    }
                    Text { text:"THESE SETTINGS APPLY THROUGHOUT THE BRIDGE."; x:28*root.scaleUnit; y:714*root.scaleUnit; width:parent.width-56*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,12*root.scaleUnit); horizontalAlignment:Text.AlignHCenter }
                }

                MetalPanel { width:parent.width; height:220*root.scaleUnit; panelColor:root.screen
                    SectionTitle { text:"SUPPORT / DIAGNOSTICS"; x:20*root.scaleUnit; y:15*root.scaleUnit; width:parent.width-40*root.scaleUnit; height:36*root.scaleUnit }
                    Text {
                        text:"If something goes wrong, export one support ZIP. API credentials are never included."
                        x:28*root.scaleUnit; y:64*root.scaleUnit; width:parent.width-430*root.scaleUnit
                        color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(11,14*root.scaleUnit); wrapMode:Text.WordWrap
                    }
                    MechanicalButton {
                        x:parent.width-382*root.scaleUnit; y:56*root.scaleUnit; width:354*root.scaleUnit; height:96*root.scaleUnit
                        text:"EXPORT SUPPORT LOG"; subtext:"DIAGNOSTICS + LOGS + RECENT ELITE JOURNALS"
                        accent:root.amber; labelScale:.65; subtextMinSize:Math.max(10,11*root.scaleUnit)
                        onClicked:bridge.requestCommand("save_data")
                    }
                    Text {
                        text:"The export opens Explorer with the generated ZIP selected so it can be attached directly to a support message."
                        x:28*root.scaleUnit; y:166*root.scaleUnit; width:parent.width-56*root.scaleUnit
                        color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,12*root.scaleUnit); wrapMode:Text.WordWrap
                    }
                }

                Item { width:1; height:140*root.scaleUnit }
            }
        }
    }



    // During the guided cockpit tour the Bridge drives the workspace. The blocker
    // begins below the header so STOP TUTORIAL (and the emergency EXIT control)
    // always remain reachable while cockpit controls stay locked.
    MouseArea {
        id: firstOrientationInputBlocker
        x: 0
        y: root.m + root.topH + root.gap
        width: parent.width
        height: parent.height - y
        z: 840
        visible: root.firstOrientationActive
        enabled: visible
        hoverEnabled: true
        preventStealing: true
        onClicked: {
            root.orientationLockNoticeVisible = true
            orientationLockNoticeTimer.restart()
        }
    }

    Timer {
        id: orientationLockNoticeTimer
        interval: 2800
        repeat: false
        onTriggered: root.orientationLockNoticeVisible = false
    }

    Rectangle {
        id: orientationLockNotice
        z: 940
        visible: root.firstOrientationActive && !root.firstOrientationPaused && root.orientationLockNoticeVisible
        x:(root.width-width)/2
        y:root.height*.40
        width:Math.min(920*root.scaleUnit, root.width-220*root.scaleUnit)
        height:150*root.scaleUnit
        color:"#300908"; border.color:root.red; border.width:Math.max(2,4*root.scaleUnit)
        opacity:.97
        SequentialAnimation on opacity {
            running:parent.visible; loops:Animation.Infinite
            NumberAnimation { to:.78; duration:360; easing.type:Easing.InOutQuad }
            NumberAnimation { to:.97; duration:360; easing.type:Easing.InOutQuad }
        }
        Text { text:"ORIENTATION MODE"; x:20*root.scaleUnit; y:20*root.scaleUnit; width:parent.width-40*root.scaleUnit; horizontalAlignment:Text.AlignHCenter; color:root.red; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(20,30*root.scaleUnit) }
        Text { text:"CONTROLS TEMPORARILY LOCKED"; x:20*root.scaleUnit; y:62*root.scaleUnit; width:parent.width-40*root.scaleUnit; horizontalAlignment:Text.AlignHCenter; color:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(16,23*root.scaleUnit) }
        Text { text:"STOP ORIENTATION TO REGAIN CONTROL"; x:20*root.scaleUnit; y:104*root.scaleUnit; width:parent.width-40*root.scaleUnit; horizontalAlignment:Text.AlignHCenter; color:"#ffd0ca"; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(15,20*root.scaleUnit) }
    }


    // Contextual page-help spotlight. The backend advances the spoken tip; this
    // single overlay follows the matching control without stealing mouse input.
    Item {
        id: pageHelpOverlay
        anchors.fill: parent
        z: 850
        visible: bridge.pageHelpActive && (bridge.pageHelpPage===root.currentPage || (root.firstOrientationActive && bridge.pageHelpPage===0)) && !root.introVisible
        property var targetItem: root.pageHelpTarget(bridge.pageHelpPage, bridge.pageHelpStep)
        // Map directly into the page-help overlay coordinate system. Mapping through root
        // caused a constant chassis/content offset on several pages because the
        // overlay and target controls do not always share the same immediate parent.
        property point targetTopLeft: {
            var tick = bridge.pulse
            if (!targetItem) return Qt.point(0, 0)
            return targetItem.mapToItem(pageHelpOverlay, 0, 0)
        }
        property point targetBottomRight: {
            var tick = bridge.pulse
            if (!targetItem) return Qt.point(0, 0)
            return targetItem.mapToItem(pageHelpOverlay, targetItem.width, targetItem.height)
        }
        property real targetX: Math.min(targetTopLeft.x, targetBottomRight.x)
        property real targetY: Math.min(targetTopLeft.y, targetBottomRight.y)
        property real targetW: Math.abs(targetBottomRight.x-targetTopLeft.x)
        property real targetH: Math.abs(targetBottomRight.y-targetTopLeft.y)

        Rectangle {
            id: helpSpotlight
            visible: pageHelpOverlay.targetItem !== null && pageHelpOverlay.targetW > 0 && pageHelpOverlay.targetH > 0
            x: Math.max(6*root.scaleUnit, pageHelpOverlay.targetX-8*root.scaleUnit)
            y: Math.max(6*root.scaleUnit, pageHelpOverlay.targetY-8*root.scaleUnit)
            width: Math.min(pageHelpOverlay.width-x-6*root.scaleUnit, pageHelpOverlay.targetW+16*root.scaleUnit)
            height: Math.min(pageHelpOverlay.height-y-6*root.scaleUnit, pageHelpOverlay.targetH+16*root.scaleUnit)
            color: "transparent"
            border.color: root.amber
            border.width: Math.max(3,4*root.scaleUnit)
            radius: Math.max(2,4*root.scaleUnit)
            opacity: .90

            SequentialAnimation on opacity {
                running: pageHelpOverlay.visible
                loops: Animation.Infinite
                NumberAnimation { to: .38; duration: 420 }
                NumberAnimation { to: 1.0; duration: 420 }
            }

            Rectangle { anchors.fill: parent; anchors.margins: -6*root.scaleUnit; color: "transparent"; border.color: root.amber; border.width: Math.max(1,2*root.scaleUnit); opacity: .34 }
            Rectangle {
                x: 10*root.scaleUnit; y: -16*root.scaleUnit
                width: Math.min(parent.width-20*root.scaleUnit, 420*root.scaleUnit); height: 30*root.scaleUnit
                color: "#251d08"; border.color: root.amber; border.width: 1
                Text { anchors.centerIn: parent; text: "BRIDGE GUIDE // "+String(bridge.pageHelpLabel || "PAGE HELP").toUpperCase(); color: root.amber; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,12*root.scaleUnit); elide:Text.ElideRight; width:parent.width-16*root.scaleUnit; horizontalAlignment:Text.AlignHCenter }
            }
        }

        // First-beat onboarding cue. It remains visible for the entire first highlighted
        // step and disappears only when the tutorial advances, never on a short timer.
        Item {
            id:tutorialIntroArrow
            visible:root.firstOrientationActive && root.firstOrientationPhase===0 && root.tutorialIntroArrowVisible && helpSpotlight.visible
            width:190*root.scaleUnit; height:104*root.scaleUnit
            x:Math.min(pageHelpOverlay.width-width-22*root.scaleUnit, helpSpotlight.x+helpSpotlight.width+34*root.scaleUnit)
            y:Math.max(112*root.scaleUnit, Math.min(pageHelpOverlay.height-height-24*root.scaleUnit, helpSpotlight.y+helpSpotlight.height*.50-height*.50))
            Canvas {
                anchors.fill:parent
                onPaint:{
                    var c=getContext("2d")
                    c.reset(); c.clearRect(0,0,width,height)
                    c.fillStyle="#f0b63b"; c.strokeStyle="#6d4f10"; c.lineWidth=Math.max(3,5*root.scaleUnit)
                    c.beginPath()
                    c.moveTo(0,height*.50)
                    c.lineTo(width*.38,height*.08)
                    c.lineTo(width*.38,height*.31)
                    c.lineTo(width*.96,height*.31)
                    c.lineTo(width*.96,height*.69)
                    c.lineTo(width*.38,height*.69)
                    c.lineTo(width*.38,height*.92)
                    c.closePath(); c.fill(); c.stroke()
                }
            }
            SequentialAnimation on opacity {
                running:parent.visible; loops:Animation.Infinite
                NumberAnimation { to:.58; duration:430; easing.type:Easing.InOutQuad }
                NumberAnimation { to:1.0; duration:430; easing.type:Easing.InOutQuad }
            }
        }
    }

    // NORMAL STARTUP PRE-FLIGHT. First-run setup owns its own readiness page,
    // so this screen appears only on later launches unless the pilot disables it.
    Rectangle {
        id: startupPreflightOverlay
        anchors.fill: parent
        z: 4800
        visible: root.startupPreflightVisible
        color: "#040504"

        Rectangle { anchors.fill:parent; color:"#020302"; opacity:.96 }
        Rectangle { anchors.fill:parent; anchors.margins:18*root.scaleUnit; color:"transparent"; border.color:"#6d644f"; border.width:2 }

        MetalPanel {
            id: startupPreflightShell
            anchors.centerIn: parent
            width: Math.min(parent.width-110*root.scaleUnit, 2020*root.scaleUnit)
            height: Math.min(parent.height-100*root.scaleUnit, 1160*root.scaleUnit)
            panelColor: "#070907"
            heavy: true

            Text { text:"ELITE AI BRIDGE // SYSTEMS CHECK"; x:42*root.scaleUnit; y:30*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(24,36*root.scaleUnit) }
            Text { text:bridge.connected?"PRE-FLIGHT":"STARTING"; anchors.right:startupExitButton.left; anchors.rightMargin:22*root.scaleUnit; y:42*root.scaleUnit; color:bridge.connected?root.green:root.amber; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(12,16*root.scaleUnit) }
            MechanicalButton { id:startupExitButton; x:parent.width-210*root.scaleUnit; y:24*root.scaleUnit; width:168*root.scaleUnit; height:62*root.scaleUnit; text:"EXIT"; subtext:"SHUT DOWN"; accent:root.red; danger:true; labelScale:.78; onClicked:root.requestBridgeExit() }
            Rectangle { x:42*root.scaleUnit; y:102*root.scaleUnit; width:parent.width-84*root.scaleUnit; height:2; color:"#394039" }

            Rectangle {
                x:42*root.scaleUnit; y:132*root.scaleUnit; width:parent.width-84*root.scaleUnit; height:116*root.scaleUnit
                color:"#061008"; border.color:!bridge.connected?root.amber:(bridge.setupReady?root.green:root.red); border.width:2
                Rectangle { x:16*root.scaleUnit; anchors.verticalCenter:parent.verticalCenter; width:16*root.scaleUnit; height:56*root.scaleUnit; color:!bridge.connected?root.amber:(bridge.setupReady?root.green:root.red); opacity:.9 }
                Text { text:!bridge.connected?"STARTING BRIDGE":(bridge.setupReady?"BRIDGE READY":"SETUP NEEDS ATTENTION"); x:48*root.scaleUnit; y:18*root.scaleUnit; color:!bridge.connected?root.amber:(bridge.setupReady?root.green:root.red); font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(17,24*root.scaleUnit) }
                Text { text:!bridge.connected?"Core services are loading. The check will begin automatically.":(bridge.setupReady?"Required controls and audio are ready. Amber items can come online later.":"One or more required items need attention before the Bridge is fully ready."); x:48*root.scaleUnit; y:59*root.scaleUnit; width:parent.width-72*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(11,14*root.scaleUnit); wrapMode:Text.WordWrap }
            }

            Text { text:"GREEN  READY     AMBER  WAITING / OPTIONAL     RED  ACTION REQUIRED"; x:42*root.scaleUnit; y:268*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,12*root.scaleUnit) }

            Grid {
                id: startupPreflightGrid
                x:42*root.scaleUnit; y:306*root.scaleUnit; width:parent.width-84*root.scaleUnit; height:590*root.scaleUnit
                columns:2; columnSpacing:16*root.scaleUnit; rowSpacing:12*root.scaleUnit
                Repeater {
                    model: root.startupPreflightRows()
                    Rectangle {
                        width:(startupPreflightGrid.width-startupPreflightGrid.columnSpacing)/2
                        height:102*root.scaleUnit
                        property color resultColor:modelData.status==="READY"?root.green:((modelData.status==="MISSING"||modelData.status==="NEEDS ATTENTION")?root.red:root.amber)
                        property bool scanHot:root.startupPreflightScanActive && index===root.startupPreflightScanIndex
                        color:scanHot?Qt.darker(resultColor,3.2):"#050b07"
                        border.color:scanHot?resultColor:(modelData.status==="READY"?"#1b6036":((modelData.status==="MISSING"||modelData.status==="NEEDS ATTENTION")?root.red:"#554822"))
                        border.width:scanHot?Math.max(2,3*root.scaleUnit):1
                        Rectangle { x:12*root.scaleUnit; anchors.verticalCenter:parent.verticalCenter; width:10*root.scaleUnit; height:48*root.scaleUnit; color:parent.resultColor; opacity:.9 }
                        Text { text:modelData.label.toUpperCase(); x:34*root.scaleUnit; y:18*root.scaleUnit; width:parent.width*.58; color:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit); elide:Text.ElideRight }
                        Text { text:modelData.status; anchors.right:parent.right; anchors.rightMargin:16*root.scaleUnit; y:18*root.scaleUnit; color:parent.resultColor; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,13*root.scaleUnit) }
                        Text { visible:root.startupPreflightDetails; text:modelData.detail; x:34*root.scaleUnit; y:54*root.scaleUnit; width:parent.width-50*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,11*root.scaleUnit); elide:Text.ElideRight }
                        Text { visible:!root.startupPreflightDetails; text:modelData.status==="READY"?"READY FOR USE":((modelData.status==="MISSING"||modelData.status==="NEEDS ATTENTION")?"REVIEW IN SETUP":"CAN COME ONLINE LATER"); x:34*root.scaleUnit; y:56*root.scaleUnit; width:parent.width-50*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,11*root.scaleUnit); elide:Text.ElideRight }
                    }
                }
            }

            FlipSwitch {
                x:42*root.scaleUnit; y:900*root.scaleUnit; width:740*root.scaleUnit; height:86*root.scaleUnit
                scaleUnit:root.scaleUnit
                text:"SHOW SYSTEMS CHECK AT STARTUP"
                subtext:checked?"THIS SCREEN WILL APPEAR NEXT LAUNCH":"START DIRECTLY IN THE BRIDGE NEXT TIME"
                checked:bridge.startupPreflightEnabled
                accent:root.green
                onToggled:function(requestedChecked){bridge.setStartupPreflightEnabled(requestedChecked);bridge.playUiCue("confirm")}
            }
            Text { text:"This is an optional startup summary. Turning it off never disables health monitoring or hides status from Setup."; x:58*root.scaleUnit; y:990*root.scaleUnit; width:720*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,11*root.scaleUnit); wrapMode:Text.WordWrap }

            Row {
                anchors.right:parent.right; anchors.rightMargin:42*root.scaleUnit; y:900*root.scaleUnit; height:86*root.scaleUnit; spacing:12*root.scaleUnit
                MechanicalButton { width:230*root.scaleUnit; height:parent.height; text:root.startupPreflightDetails?"HIDE DETAILS":"SHOW DETAILS"; subtext:"CHECK INFORMATION"; accent:root.amber; labelScale:.72; onClicked:{root.startupPreflightDetails=!root.startupPreflightDetails;bridge.playUiCue("nav")} }
                MechanicalButton { width:230*root.scaleUnit; height:parent.height; text:root.startupPreflightScanActive?"CHECKING...":"REFRESH"; subtext:"RUN SYSTEM CHECK"; accent:root.green; labelScale:.78; enabled:bridge.connected&&!root.startupPreflightScanActive; opacity:enabled?1.0:.5; onClicked:root.runStartupPreflight(true) }
                MechanicalButton { visible:bridge.connected&&!bridge.setupReady; width:260*root.scaleUnit; height:parent.height; text:"CONTINUE ANYWAY"; subtext:"THIS SESSION"; accent:root.amber; labelScale:.68; onClicked:{root.startupPreflightSessionDismissed=true;bridge.playUiCue("warn")} }
                MechanicalButton { width:300*root.scaleUnit; height:parent.height; text:!bridge.connected?"STARTING...":(bridge.setupReady?"ENTER BRIDGE":"OPEN SETUP"); subtext:!bridge.connected?"WAIT FOR CORE SERVICES":(bridge.setupReady?"SYSTEMS READY":"FIX REQUIRED ITEMS"); accent:bridge.setupReady?root.green:root.amber; labelScale:.72; enabled:bridge.connected; opacity:enabled?1.0:.5; onClicked:{if(bridge.setupReady){root.startupPreflightSessionDismissed=true;bridge.playUiCue("confirm")}else{root.startupPreflightSessionDismissed=true;root.currentPage=8;bridge.playUiCue("nav")}} }
            }
        }
    }

    // FIRST-RUN GUIDED SETUP. This overlays the cockpit and can be reopened from Setup.
    Rectangle {
        id: firstRunSetupOverlay
        anchors.fill: parent
        z: 5000
        visible: root.introVisible
        color: "#050504"

        Rectangle { anchors.fill:parent; color:"#020302"; opacity:.94 }
        Rectangle { anchors.fill:parent; anchors.margins:18*root.scaleUnit; color:"transparent"; border.color:"#6d644f"; border.width:2 }

        MetalPanel {
            id: introShell
            anchors.centerIn: parent
            width: Math.min(parent.width-100*root.scaleUnit, 2180*root.scaleUnit)
            height: Math.min(parent.height-90*root.scaleUnit, 1260*root.scaleUnit)
            panelColor: "#070907"
            heavy: true

            Text { text:"ELITE AI BRIDGE // SETUP"; x:42*root.scaleUnit; y:30*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(25,38*root.scaleUnit) }
            Text { text:"CHOOSE YOUR BRIDGE"; anchors.right:parent.right; anchors.rightMargin:42*root.scaleUnit; y:42*root.scaleUnit; color:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(12,16*root.scaleUnit) }
            Rectangle { x:42*root.scaleUnit; y:94*root.scaleUnit; width:parent.width-84*root.scaleUnit; height:2; color:"#394039" }

            Column {
                id: introSteps
                x:42*root.scaleUnit; y:132*root.scaleUnit
                width:300*root.scaleUnit; spacing:12*root.scaleUnit
                Repeater {
                    model:root.wizardSteps
                    Rectangle {
                        property bool isCurrent:Number(modelData.step)===root.introStep
                        property int currentPos:root.wizardStepPosition(root.introStep)
                        width:introSteps.width; height:76*root.scaleUnit
                        color:isCurrent?"#0b2115":"#080a08"
                        border.color:isCurrent?root.green:(index<currentPos?root.dimGreen:"#3a4039")
                        border.width:isCurrent?2:1
                        Text { text:(index+1)+""; x:14*root.scaleUnit; anchors.verticalCenter:parent.verticalCenter; color:index<=parent.currentPos?root.green:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(16,21*root.scaleUnit) }
                        Text { text:modelData.label; x:54*root.scaleUnit; anchors.verticalCenter:parent.verticalCenter; width:parent.width-68*root.scaleUnit; color:parent.isCurrent?root.whiteText:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(12,15*root.scaleUnit); elide:Text.ElideRight }
                    }
                }
            }

            Rectangle {
                id: introContent
                x:370*root.scaleUnit; y:132*root.scaleUnit
                width:parent.width-x-42*root.scaleUnit; height:parent.height-y-150*root.scaleUnit
                color:"#040704"; border.color:"#324336"; border.width:1

                Item {
                    anchors.fill:parent; visible:root.introStep===0
                    Text { text:"CHOOSE YOUR EXPERIENCE"; x:34*root.scaleUnit; y:28*root.scaleUnit; color:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(24,34*root.scaleUnit) }
                    Text { text:"Choose how you want to control the Bridge. Core Bridge is the complete buttons + automation experience. AI Co-Pilot adds conversational voice control on top of it."; x:34*root.scaleUnit; y:90*root.scaleUnit; width:parent.width-68*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(13,17*root.scaleUnit); wrapMode:Text.WordWrap }
                    Rectangle { x:34*root.scaleUnit; y:166*root.scaleUnit; width:parent.width-68*root.scaleUnit; height:430*root.scaleUnit; color:"#061008"; border.color:"#244a30"; border.width:1
                        Text { text:"CHOOSE ONE"; x:18*root.scaleUnit; y:14*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(12,15*root.scaleUnit) }
                        Row { x:18*root.scaleUnit; y:52*root.scaleUnit; width:parent.width-36*root.scaleUnit; height:178*root.scaleUnit; spacing:18*root.scaleUnit
                            MechanicalButton { width:(parent.width-parent.spacing)/2; height:parent.height; text:"CORE BRIDGE"; subtext:"BUTTONS + AUTOMATION + BRIDGE VOICE"; accent:root.green; stateful:true; active:root.wizardPath==="CORE"; labelScale:.72; subtextMinSize:Math.max(9,11*root.scaleUnit); onClicked:root.selectWizardPath("CORE") }
                            MechanicalButton { width:(parent.width-parent.spacing)/2; height:parent.height; text:"AI CO-PILOT (RECOMMENDED)"; subtext:"AI VOICE + BUTTONS + AUTOMATION"; accent:root.green; stateful:true; active:root.wizardPath==="COPILOT"; labelScale:.62; subtextMinSize:Math.max(9,11*root.scaleUnit); onClicked:root.selectWizardPath("COPILOT") }
                        }
                        Row { x:18*root.scaleUnit; y:250*root.scaleUnit; width:parent.width-36*root.scaleUnit; height:126*root.scaleUnit; spacing:18*root.scaleUnit
                            Rectangle { width:(parent.width-parent.spacing)/2; height:parent.height; color:"#090b07"; border.color:root.wizardPath==="CORE"?root.green:"#554b32"; border.width:root.wizardPath==="CORE"?2:1
                                Item { x:14*root.scaleUnit; anchors.verticalCenter:parent.verticalCenter; width:92*root.scaleUnit; height:76*root.scaleUnit
                                    Repeater { model:6; Rectangle { width:20*root.scaleUnit; height:20*root.scaleUnit; x:(index%3)*28*root.scaleUnit; y:Math.floor(index/3)*30*root.scaleUnit; color:index===1||index===4?root.amber:"#17251a"; border.color:index===1||index===4?"#f0ca72":"#58705d"; border.width:1 } }
                                }
                                Text { x:122*root.scaleUnit; y:14*root.scaleUnit; width:parent.width-138*root.scaleUnit; height:parent.height-28*root.scaleUnit; text:"HANDS-ON CONTROL\nButtons, Stream Deck, spoken confirmations, alerts and built-in automation. No AI account or API key required."; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(10,12*root.scaleUnit); wrapMode:Text.WordWrap; verticalAlignment:Text.AlignVCenter }
                            }
                            Rectangle { width:(parent.width-parent.spacing)/2; height:parent.height; color:"#050b0d"; border.color:root.wizardPath==="COPILOT"?root.green:"#315864"; border.width:root.wizardPath==="COPILOT"?2:1
                                VoiceWave { x:14*root.scaleUnit; anchors.verticalCenter:parent.verticalCenter; width:92*root.scaleUnit; height:70*root.scaleUnit; color:"#55d7ff"; activeColor:root.green; speaking:true; listening:false; phase:bridge.pulse }
                                Text { x:122*root.scaleUnit; y:14*root.scaleUnit; width:parent.width-138*root.scaleUnit; height:parent.height-28*root.scaleUnit; text:"CONVERSATIONAL CO-PILOT\nEverything in Core Bridge, plus natural voice commands and AI assistance while you fly. Requires a third-party OpenAI API key; API usage may incur charges."; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(10,12*root.scaleUnit); wrapMode:Text.WordWrap; verticalAlignment:Text.AlignVCenter }
                            }
                        }
                        Text { text:root.wizardPath.length?"YOU CAN CHANGE MODES LATER FROM SETUP.":"SELECT A MODE TO CONTINUE."; x:18*root.scaleUnit; y:396*root.scaleUnit; width:parent.width-36*root.scaleUnit; color:root.wizardPath.length?root.green:root.amber; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,13*root.scaleUnit); horizontalAlignment:Text.AlignHCenter }
                    }
                    Text { text:"Elite can be connected later. Missing game data or bindings only limit the features that depend on them."; x:34*root.scaleUnit; y:624*root.scaleUnit; width:parent.width-68*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,13*root.scaleUnit); wrapMode:Text.WordWrap }
                }

                Item {
                    anchors.fill:parent; visible:root.introStep===1
                    Text { text:"AUDIO SETUP"; x:34*root.scaleUnit; y:28*root.scaleUnit; color:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(22,31*root.scaleUnit) }
                    Text { text:"Choose audio devices and test the Bridge voice."; x:34*root.scaleUnit; y:82*root.scaleUnit; width:parent.width-68*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(12,16*root.scaleUnit); wrapMode:Text.WordWrap }

                    Row { x:34*root.scaleUnit; y:170*root.scaleUnit; width:parent.width-68*root.scaleUnit; height:88*root.scaleUnit; spacing:18*root.scaleUnit
                        Column { width:(parent.width-parent.spacing)/2; spacing:7*root.scaleUnit
                            Text { text:"OUTPUT DEVICE"; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit) }
                            CockpitComboBox { width:parent.width; height:54*root.scaleUnit; scaleUnit:root.scaleUnit; accentColor:root.green; textColor:root.whiteText; mutedColor:root.muted; model:bridge.audioOutputDevices; currentIndex:root.listIndexOf(bridge.audioOutputDevices,bridge.voiceOutputDevice); onActivated:bridge.setAudioDevice("output",currentText) }
                        }
                        Column { width:(parent.width-parent.spacing)/2; spacing:7*root.scaleUnit
                            Text { text:"MICROPHONE"; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit) }
                            CockpitComboBox { width:parent.width; height:54*root.scaleUnit; scaleUnit:root.scaleUnit; accentColor:root.green; textColor:root.whiteText; mutedColor:root.muted; model:bridge.audioInputDevices; currentIndex:root.listIndexOf(bridge.audioInputDevices,bridge.voiceInputDevice); onActivated:bridge.setAudioDevice("input",currentText) }
                        }
                    }

                    Item { x:34*root.scaleUnit; y:292*root.scaleUnit; width:parent.width-68*root.scaleUnit; height:104*root.scaleUnit
                        MechanicalButton { id:introAudioTestButton; anchors.fill:parent; text:"TEST BRIDGE VOICE"; subtext:"HEAR THE SELECTED OUTPUT DEVICE"; accent:root.green; labelScale:.82; onClicked:{root.wizardAudioTested=true;bridge.requestCommand("voice_test")} }
                        Rectangle {
                            anchors.fill:parent; anchors.margins:-8*root.scaleUnit
                            visible:root.introStep===1 && !root.wizardAudioTested
                            color:"transparent"; border.color:root.amber; border.width:Math.max(2,3*root.scaleUnit); radius:Math.max(3,5*root.scaleUnit)
                            SequentialAnimation on opacity {
                                running:parent.visible; loops:Animation.Infinite
                                NumberAnimation { to:.32; duration:420 }
                                NumberAnimation { to:1.0; duration:420 }
                            }
                        }
                    }

                    Rectangle { x:34*root.scaleUnit; y:420*root.scaleUnit; width:parent.width-68*root.scaleUnit; height:164*root.scaleUnit; color:"#050b07"; border.color:"#244a30"; border.width:1
                        Text { text:"AUDIO PATH"; x:16*root.scaleUnit; y:14*root.scaleUnit; color:root.amber; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit) }
                        Text { text:"OUTPUT"; x:16*root.scaleUnit; y:52*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,13*root.scaleUnit) }
                        Text { text:bridge.voiceOutputDevice; x:150*root.scaleUnit; y:52*root.scaleUnit; width:parent.width-172*root.scaleUnit; color:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,13*root.scaleUnit); elide:Text.ElideRight }
                        Text { text:"MICROPHONE"; x:16*root.scaleUnit; y:91*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,13*root.scaleUnit) }
                        Text { text:bridge.voiceInputDevice; x:150*root.scaleUnit; y:91*root.scaleUnit; width:parent.width-172*root.scaleUnit; color:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,13*root.scaleUnit); elide:Text.ElideRight }
                        Text { text:root.wizardPath==="COPILOT"?"NEXT // CONNECT AI CO-PILOT.":"NEXT // CHOOSE YOUR BRIDGE VOICE."; x:16*root.scaleUnit; y:128*root.scaleUnit; width:parent.width-32*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(10,12*root.scaleUnit); elide:Text.ElideRight }
                    }
                }

                Item {
                    anchors.fill:parent; visible:root.introStep===4
                    Text { text:"PUSH-TO-TALK"; x:34*root.scaleUnit; y:24*root.scaleUnit; color:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(21,30*root.scaleUnit) }
                    Text { text:bridge.aiApiVerified?"AI Co-Pilot is verified. Map or test Push-to-Talk.":"Push-to-Talk is locked until the OpenAI API key is verified."; x:34*root.scaleUnit; y:72*root.scaleUnit; width:parent.width-68*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(11,15*root.scaleUnit); wrapMode:Text.WordWrap }

                    Rectangle { x:34*root.scaleUnit; y:142*root.scaleUnit; width:parent.width-68*root.scaleUnit; height:116*root.scaleUnit; color:"#061008"; border.color:bridge.pttStatus==="MAPPING"?root.amber:(bridge.pttStatus==="READY"?root.green:root.red); border.width:2
                        Text { text:"PUSH-TO-TALK"; x:18*root.scaleUnit; y:12*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit) }
                        Text { text:bridge.voicePttMapping; x:18*root.scaleUnit; y:40*root.scaleUnit; width:parent.width-36*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(13,17*root.scaleUnit); elide:Text.ElideRight }
                        Text { text:"KEYBOARD / STREAM DECK  //  CTRL + ALT + SHIFT + V"; x:18*root.scaleUnit; y:78*root.scaleUnit; width:parent.width-36*root.scaleUnit; color:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,13*root.scaleUnit); elide:Text.ElideRight }
                    }

                    Item { x:34*root.scaleUnit; y:278*root.scaleUnit; width:parent.width-68*root.scaleUnit; height:82*root.scaleUnit
                        MechanicalButton { id:introMapPttButton; anchors.fill:parent; enabled:bridge.aiApiVerified; opacity:enabled?1.0:.45; text:bridge.pttStatus==="MAPPING"?"CANCEL PTT MAP":"MAP HOTAS / GAMEPAD PTT"; subtext:bridge.pttStatus==="MAPPING"?"PRESS HOTAS / GAMEPAD CONTROL":"OPTIONAL // KEYBOARD PTT ALREADY WORKS"; accent:bridge.pttStatus==="MAPPING"?root.amber:root.green; labelScale:.70; onClicked:{if(!bridge.wizardNarrationActive)bridge.playUiCue("confirm");root.wizardPttMapStarted=true;bridge.requestCommand("ptt_map")} }
                        Rectangle {
                            z:20; anchors.fill:parent; anchors.margins:-9*root.scaleUnit
                            visible:root.introStep===4 && bridge.pttStatus!=="READY"
                            color:"transparent"; opacity:.28; border.color:root.amber; border.width:Math.max(3,4*root.scaleUnit); radius:Math.max(4,6*root.scaleUnit)
                            SequentialAnimation on opacity {
                                running:parent.visible; loops:Animation.Infinite
                                NumberAnimation { to:.28; duration:360 }
                                NumberAnimation { to:1.0; duration:360 }
                            }
                            Rectangle { anchors.fill:parent; anchors.margins:-6*root.scaleUnit; color:"transparent"; border.color:"#ffd76a"; border.width:Math.max(1,2*root.scaleUnit); opacity:.80 }
                        }
                    }

                    Rectangle { x:34*root.scaleUnit; y:382*root.scaleUnit; width:parent.width-68*root.scaleUnit; height:222*root.scaleUnit; color:"#050b07"; border.color:bridge.voiceInputStatus.indexOf("PASS")>=0?root.green:((bridge.voiceInputStatus.toUpperCase().indexOf("FAIL")>=0 || bridge.voiceInputStatus.toUpperCase().indexOf("UNAVAILABLE")>=0)?root.red:root.amber); border.width:2
                        Text { text:"LIVE PTT PROOF"; x:18*root.scaleUnit; y:14*root.scaleUnit; color:root.amber; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,15*root.scaleUnit) }
                        Text { text:"1  HOLD YOUR PTT
2  SAY:  BRIDGE MICROPHONE CHECK
3  RELEASE PTT
4  WATCH FOR PTT PASS + MIC PASS + TRANSCRIPTION FEEDBACK"; x:18*root.scaleUnit; y:48*root.scaleUnit; width:parent.width-36*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit); lineHeight:1.28 }
                        Text { text:bridge.voiceInputStatus; x:18*root.scaleUnit; y:146*root.scaleUnit; width:parent.width-36*root.scaleUnit; color:bridge.voiceInputStatus.indexOf("PASS")>=0?root.green:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(10,13*root.scaleUnit); wrapMode:Text.WordWrap }
                        Text { text:"HEARD // "+bridge.voiceLastText; x:18*root.scaleUnit; y:190*root.scaleUnit; width:parent.width-36*root.scaleUnit; color:bridge.voiceLastText!=="-"?root.green:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,13*root.scaleUnit); elide:Text.ElideRight }
                    }
                }

                Item {
                    anchors.fill:parent; visible:root.introStep===3
                    Text { text:"BRIDGE VOICE + TALK LEVEL"; x:34*root.scaleUnit; y:20*root.scaleUnit; color:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(20,29*root.scaleUnit) }
                    Text { text:"Choose the voice used for Bridge confirmations, alerts and automation feedback. This voice is used in both Core Bridge and AI Co-Pilot. Choose how much Bridge talks and what it should call you; everything can be changed later from Setup."; x:34*root.scaleUnit; y:64*root.scaleUnit; width:parent.width-68*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(10,13*root.scaleUnit); wrapMode:Text.WordWrap }

                    Row { x:34*root.scaleUnit; y:112*root.scaleUnit; width:parent.width-68*root.scaleUnit; height:64*root.scaleUnit; spacing:14*root.scaleUnit
                        Column { width:(parent.width-parent.spacing)/2; spacing:4*root.scaleUnit
                            Text { text:"VOICE"; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,12*root.scaleUnit) }
                            CockpitComboBox { width:parent.width; height:44*root.scaleUnit; scaleUnit:root.scaleUnit; accentColor:root.green; textColor:root.whiteText; mutedColor:root.muted; model:bridge.voiceNameOptions; currentIndex:root.listIndexOf(bridge.voiceNameOptions,bridge.voiceName); onActivated:bridge.setVoiceTuning("name",currentText) }
                        }
                        Column { width:(parent.width-parent.spacing)/2; spacing:4*root.scaleUnit
                            Text { text:"PITCH"; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,12*root.scaleUnit) }
                            CockpitComboBox { width:parent.width; height:44*root.scaleUnit; scaleUnit:root.scaleUnit; accentColor:root.green; textColor:root.whiteText; mutedColor:root.muted; model:bridge.voicePitchOptions; currentIndex:root.listIndexOf(bridge.voicePitchOptions,bridge.voicePitch); onActivated:bridge.setVoiceTuning("pitch",currentText) }
                        }
                    }
                    Row { x:34*root.scaleUnit; y:188*root.scaleUnit; width:parent.width-68*root.scaleUnit; height:64*root.scaleUnit; spacing:14*root.scaleUnit
                        Column { width:(parent.width-parent.spacing)/2; spacing:4*root.scaleUnit
                            Text { text:"VOICE CHARACTER"; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,12*root.scaleUnit) }
                            CockpitComboBox { width:parent.width; height:44*root.scaleUnit; scaleUnit:root.scaleUnit; accentColor:root.green; textColor:root.whiteText; mutedColor:root.muted; model:bridge.voiceEffectOptions; currentIndex:root.listIndexOf(bridge.voiceEffectOptions,bridge.voiceEffect); onActivated:bridge.setVoiceTuning("effect",currentText) }
                        }
                        Column { width:(parent.width-parent.spacing)/2; spacing:4*root.scaleUnit
                            Text { text:"WHAT SHOULD BRIDGE CALL YOU?"; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,12*root.scaleUnit) }
                            Item { width:parent.width; height:54*root.scaleUnit
                                Row { id:introCallNameRow; anchors.fill:parent; spacing:8*root.scaleUnit
                                    Rectangle { width:parent.width-278*root.scaleUnit; height:54*root.scaleUnit; color:"#061008"; border.color:introCallNameInput.activeFocus?root.green:"#244a30"; border.width:1
                                        TextInput { id:introCallNameInput; text:root.introCommanderDraft; anchors.fill:parent; anchors.margins:10*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(11,14*root.scaleUnit); verticalAlignment:TextInput.AlignVCenter; selectByMouse:true; onActiveFocusChanged:if(activeFocus)root.wizardCallNameTouched=true; onTextEdited:{root.wizardCallNameTouched=true;root.introCommanderDraft=text} Keys.onReturnPressed:{root.wizardCallNameTouched=true;bridge.setSetupValue("commander_address",root.introCommanderDraft);bridge.playUiCue("confirm")} }
                                    }
                                    MechanicalButton { width:270*root.scaleUnit; height:54*root.scaleUnit; text:"SAVE CALL NAME"; subtext:""; accent:root.green; labelScale:.72; onClicked:{root.wizardCallNameTouched=true;bridge.setSetupValue("commander_address",root.introCommanderDraft);bridge.playUiCue("confirm")} }
                                }
                                Rectangle {
                                    anchors.fill:parent; anchors.margins:-7*root.scaleUnit
                                    visible:root.introStep===3 && !root.wizardCallNameTouched
                                    color:"transparent"; border.color:root.amber; border.width:Math.max(2,3*root.scaleUnit); radius:Math.max(3,5*root.scaleUnit)
                                    SequentialAnimation on opacity {
                                    running: parent.visible
                                    loops: Animation.Infinite
                                    NumberAnimation { to: .32; duration: 420 }
                                    NumberAnimation { to: 1.0; duration: 420 }
                                }
                                    Rectangle { anchors.fill:parent; anchors.margins:-5*root.scaleUnit; color:"transparent"; border.color:root.amber; border.width:1; opacity:.35 }
                                }
                            }
                        }
                    }

                    Text { text:"VOICE VOLUME"; x:34*root.scaleUnit; y:276*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,12*root.scaleUnit) }
                    Text { text:Math.round(root.introVoiceVolumeDraft)+"%"; x:parent.width/2-92*root.scaleUnit; y:276*root.scaleUnit; width:54*root.scaleUnit; horizontalAlignment:Text.AlignRight; color:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,12*root.scaleUnit) }
                    Row { x:34*root.scaleUnit; y:296*root.scaleUnit; width:parent.width/2-68*root.scaleUnit; height:38*root.scaleUnit; spacing:8*root.scaleUnit
                        Rectangle { width:38*root.scaleUnit; height:38*root.scaleUnit; color:volMinusMouse.pressed?"#18331f":"#0a120c"; border.color:volMinusMouse.containsMouse?root.green:"#35523e"; border.width:1
                            Text { anchors.centerIn:parent; text:"−"; color:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(15,20*root.scaleUnit) }
                            MouseArea { id:volMinusMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; onClicked:{root.introVoiceVolumeDraft=Math.max(0,Math.round(root.introVoiceVolumeDraft)-5);bridge.setAudioLevel("voice",root.introVoiceVolumeDraft);bridge.playUiCue("confirm")} }
                        }
                        Slider { id:introVoiceVolumeSlider; width:parent.width-92*root.scaleUnit; height:parent.height; from:0; to:100; stepSize:0; value:root.introVoiceVolumeDraft; onMoved:root.introVoiceVolumeDraft=value; onPressedChanged:if(!pressed){root.introVoiceVolumeDraft=Math.round(value);bridge.setAudioLevel("voice",root.introVoiceVolumeDraft)} }
                        Rectangle { width:38*root.scaleUnit; height:38*root.scaleUnit; color:volPlusMouse.pressed?"#18331f":"#0a120c"; border.color:volPlusMouse.containsMouse?root.green:"#35523e"; border.width:1
                            Text { anchors.centerIn:parent; text:"+"; color:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(15,20*root.scaleUnit) }
                            MouseArea { id:volPlusMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; onClicked:{root.introVoiceVolumeDraft=Math.min(100,Math.round(root.introVoiceVolumeDraft)+5);bridge.setAudioLevel("voice",root.introVoiceVolumeDraft);bridge.playUiCue("confirm")} }
                        }
                    }
                    Text { text:"SPEECH SPEED"; x:parent.width/2+10*root.scaleUnit; y:276*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,12*root.scaleUnit) }
                    Text { text:Number(root.introVoiceSpeedDraft).toFixed(2)+"x"; x:parent.width-96*root.scaleUnit; y:276*root.scaleUnit; width:62*root.scaleUnit; horizontalAlignment:Text.AlignRight; color:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,12*root.scaleUnit) }
                    Row { x:parent.width/2+10*root.scaleUnit; y:296*root.scaleUnit; width:parent.width/2-44*root.scaleUnit; height:38*root.scaleUnit; spacing:8*root.scaleUnit
                        Rectangle { width:38*root.scaleUnit; height:38*root.scaleUnit; color:speedMinusMouse.pressed?"#18331f":"#0a120c"; border.color:speedMinusMouse.containsMouse?root.green:"#35523e"; border.width:1
                            Text { anchors.centerIn:parent; text:"−"; color:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(15,20*root.scaleUnit) }
                            MouseArea { id:speedMinusMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; onClicked:{root.introVoiceSpeedDraft=Math.max(.7,Math.round((root.introVoiceSpeedDraft-.05)*20)/20);bridge.setVoiceTuningNumber("speed",root.introVoiceSpeedDraft);bridge.playUiCue("confirm")} }
                        }
                        Slider { id:introVoiceSpeedSlider; width:parent.width-92*root.scaleUnit; height:parent.height; from:.7; to:2.0; stepSize:0; value:root.introVoiceSpeedDraft; onMoved:root.introVoiceSpeedDraft=value; onPressedChanged:if(!pressed){root.introVoiceSpeedDraft=Math.round(value*20)/20;bridge.setVoiceTuningNumber("speed",root.introVoiceSpeedDraft)} }
                        Rectangle { width:38*root.scaleUnit; height:38*root.scaleUnit; color:speedPlusMouse.pressed?"#18331f":"#0a120c"; border.color:speedPlusMouse.containsMouse?root.green:"#35523e"; border.width:1
                            Text { anchors.centerIn:parent; text:"+"; color:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(15,20*root.scaleUnit) }
                            MouseArea { id:speedPlusMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; onClicked:{root.introVoiceSpeedDraft=Math.min(2.0,Math.round((root.introVoiceSpeedDraft+.05)*20)/20);bridge.setVoiceTuningNumber("speed",root.introVoiceSpeedDraft);bridge.playUiCue("confirm")} }
                        }
                    }

                    Text { text:"CHOOSE HOW MUCH THE BRIDGE TALKS. BALANCED IS THE DEFAULT."; x:34*root.scaleUnit; y:360*root.scaleUnit; width:parent.width-68*root.scaleUnit; color:root.amber; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,11*root.scaleUnit); horizontalAlignment:Text.AlignHCenter; wrapMode:Text.WordWrap }
                    Item {
                        id:introTalkLevelGroup
                        x:34*root.scaleUnit; y:394*root.scaleUnit; width:parent.width-68*root.scaleUnit; height:126*root.scaleUnit
                        Row {
                            anchors.fill:parent; spacing:10*root.scaleUnit
                            MechanicalButton {
                                width:(parent.width-parent.spacing*2)/3; height:parent.height
                                text:"QUIET"; subtext:"ESSENTIAL ALERTS ONLY"; accent:root.green; inactiveAccent:"#302817"; stateful:true; labelScale:.78
                                active:bridge.voiceAttentionMode==="OFF"
                                onClicked:{root.wizardTalkLevelTouched=true;bridge.setVoiceAttention("OFF");bridge.playUiCue("confirm")}
                            }
                            MechanicalButton {
                                width:(parent.width-parent.spacing*2)/3; height:parent.height
                                text:"BALANCED"; subtext:"DEFAULT // OPERATIONAL"; accent:root.green; inactiveAccent:"#302817"; stateful:true; labelScale:.78
                                active:bridge.voiceAttentionMode==="IMPORTANT"
                                onClicked:{root.wizardTalkLevelTouched=true;bridge.setVoiceAttention("IMPORTANT");bridge.playUiCue("confirm")}
                            }
                            MechanicalButton {
                                width:(parent.width-parent.spacing*2)/3; height:parent.height
                                text:"TALKATIVE"; subtext:"MOST ACTIVE"; accent:root.green; inactiveAccent:"#302817"; stateful:true; labelScale:.78
                                active:bridge.voiceAttentionMode==="MOST"
                                onClicked:{root.wizardTalkLevelTouched=true;bridge.setVoiceAttention("MOST");bridge.playUiCue("confirm")}
                            }
                        }
                        Rectangle {
                            anchors.fill:parent; anchors.margins:-8*root.scaleUnit
                            visible:root.introStep===3 && !root.wizardTalkLevelTouched
                            color:"transparent"; border.color:root.amber; border.width:Math.max(2,3*root.scaleUnit); radius:Math.max(3,5*root.scaleUnit)
                            SequentialAnimation on opacity {
                                running:parent.visible; loops:Animation.Infinite
                                NumberAnimation { to:.32; duration:420 }
                                NumberAnimation { to:1.0; duration:420 }
                            }
                            Rectangle { anchors.fill:parent; anchors.margins:-5*root.scaleUnit; color:"transparent"; border.color:root.amber; border.width:1; opacity:.35 }
                        }
                    }
                    MechanicalButton {
                        x:(parent.width-900*root.scaleUnit)/2; y:558*root.scaleUnit; width:900*root.scaleUnit; height:118*root.scaleUnit
                        text:(root.introCommanderDraft.trim().length>0?("TEST "+root.introCommanderDraft.trim().toUpperCase()):"TEST COMMANDER")
                        subtext:"SAVE CALL NAME + HEAR CURRENT VOICE"
                        accent:root.green; labelScale:.90; subtextMinSize:Math.max(11,14*root.scaleUnit)
                        onClicked:{if(root.introCommanderDraft.trim().length>0)bridge.setSetupValue("commander_address",root.introCommanderDraft.trim());bridge.requestCommand("voice_test")}
                    }
                    Text { text:"Your call name and voice can be changed later from Setup."; x:34*root.scaleUnit; y:692*root.scaleUnit; width:parent.width-68*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,10*root.scaleUnit); horizontalAlignment:Text.AlignHCenter; wrapMode:Text.WordWrap }
                }

                Item {
                    anchors.fill:parent; visible:root.introStep===2
                    Text { text:"AI CO-PILOT // OPENAI CONNECTION"; x:34*root.scaleUnit; y:24*root.scaleUnit; color:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(21,30*root.scaleUnit) }
                    Text { text:"AI Co-Pilot requires a working OpenAI API key. Save and verify the key before continuing."; x:34*root.scaleUnit; y:70*root.scaleUnit; width:parent.width-68*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(11,15*root.scaleUnit); wrapMode:Text.WordWrap }

                    Rectangle { x:34*root.scaleUnit; y:124*root.scaleUnit; width:parent.width-68*root.scaleUnit; height:88*root.scaleUnit; color:"#061008"; border.color:bridge.aiApiVerified?root.green:(bridge.aiApiVerifyStatus==="FAILED"?root.red:root.amber); border.width:2
                        Text { text:bridge.aiApiVerified?"CO-PILOT VERIFIED":(bridge.aiApiVerifyStatus==="VERIFYING"?"VERIFYING OPENAI CONNECTION...":(bridge.aiApiVerifyStatus==="FAILED"?"API KEY NOT VERIFIED":"CO-PILOT NEEDS A VERIFIED KEY")); x:16*root.scaleUnit; y:12*root.scaleUnit; color:bridge.aiApiVerified?root.green:(bridge.aiApiVerifyStatus==="FAILED"?root.red:root.amber); font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,15*root.scaleUnit) }
                        Text { text:bridge.aiApiVerified?"The AI Co-Pilot path is ready to continue.":bridge.aiApiVerifyDetail; x:16*root.scaleUnit; y:44*root.scaleUnit; width:parent.width-32*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(10,12*root.scaleUnit); elide:Text.ElideRight }
                    }

                    MechanicalButton { x:34*root.scaleUnit; y:224*root.scaleUnit; width:620*root.scaleUnit; height:96*root.scaleUnit; text:"HELP GETTING AN API KEY"; subtext:"STEP-BY-STEP"; accent:root.green; labelScale:.92; subtextMinSize:Math.max(11,14*root.scaleUnit); onClicked:{bridge.openExternalHelp("chatgpt_api_help")} }
                    Row { x:34*root.scaleUnit; y:328*root.scaleUnit; width:620*root.scaleUnit; height:54*root.scaleUnit; spacing:12*root.scaleUnit
                        MechanicalButton { width:(parent.width-parent.spacing)/2; height:parent.height; text:"OPEN API KEYS"; subtext:"OPENAI"; accent:root.muted; labelScale:.68; onClicked:{bridge.openExternalHelp("api_keys")} }
                        MechanicalButton { width:(parent.width-parent.spacing)/2; height:parent.height; text:"API BILLING"; subtext:"CREDITS / USAGE"; accent:root.muted; labelScale:.68; onClicked:{bridge.openExternalHelp("api_billing")} }
                    }

                    Rectangle { x:34*root.scaleUnit; y:398*root.scaleUnit; width:parent.width-68*root.scaleUnit; height:80*root.scaleUnit; color:"#050b07"; border.color:"#244a30"; border.width:1
                        Text { text:"1  Paste your OpenAI API key below.
2  Choose SAVE + VERIFY. Bridge makes one tiny test request.
3  NEXT unlocks only after verification succeeds."; x:16*root.scaleUnit; y:16*root.scaleUnit; width:parent.width-32*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(10,13*root.scaleUnit); lineHeight:1.35; wrapMode:Text.WordWrap }
                    }

                    Text { text:"OPENAI API KEY"; x:34*root.scaleUnit; y:500*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(11,14*root.scaleUnit) }
                    Text { text:bridge.aiApiVerified?("VERIFIED // ENDING "+bridge.setupApiKeyLast4):(bridge.aiApiConfigured?("SAVED // ENDING "+bridge.setupApiKeyLast4):"NO VERIFIED KEY"); anchors.right:parent.right; anchors.rightMargin:34*root.scaleUnit; y:500*root.scaleUnit; color:bridge.aiApiVerified?root.green:root.amber; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,13*root.scaleUnit) }
                    Rectangle { x:34*root.scaleUnit; y:528*root.scaleUnit; width:parent.width-420*root.scaleUnit; height:64*root.scaleUnit; color:"#061008"; border.color:introApiInput.activeFocus?root.green:"#244a30"; border.width:1
                        TextInput { id:introApiInput; text:root.introApiKeyDraft; anchors.fill:parent; anchors.margins:10*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(13,16*root.scaleUnit); verticalAlignment:TextInput.AlignVCenter; selectByMouse:true; echoMode:TextInput.Password; onTextEdited:root.introApiKeyDraft=text }
                    }
                    MechanicalButton {
                        x:parent.width-372*root.scaleUnit; y:496*root.scaleUnit; width:338*root.scaleUnit; height:72*root.scaleUnit
                        text:bridge.aiApiVerifyStatus==="VERIFYING"?"VERIFYING...":(root.introApiKeyDraft.trim().length>0?"SAVE + VERIFY API KEY":"VERIFY SAVED KEY")
                        subtext:bridge.aiApiVerified?"CONNECTION VERIFIED":"REQUIRED TO CONTINUE"
                        accent:bridge.aiApiVerified?root.green:root.amber; labelScale:.60
                        enabled:bridge.aiApiVerifyStatus!=="VERIFYING" && (root.introApiKeyDraft.trim().length>0 || bridge.aiApiConfigured)
                        opacity:enabled?1.0:.48
                        onClicked:{if(root.introApiKeyDraft.trim().length>0){bridge.saveApiKey(root.introApiKeyDraft);root.introApiKeyDraft=""}else{bridge.requestCommand("setup_api_key_verify")}}
                    }
                    Text { text:"OpenAI is a third-party service. API usage may incur charges from OpenAI."; x:34*root.scaleUnit; y:582*root.scaleUnit; width:parent.width-68*root.scaleUnit; color:root.amber; font.family:"Consolas"; font.pixelSize:Math.max(10,11*root.scaleUnit); wrapMode:Text.WordWrap }

                    Rectangle { x:34*root.scaleUnit; y:626*root.scaleUnit; width:parent.width-68*root.scaleUnit; height:112*root.scaleUnit; color:"#080a08"; border.color:"#514824"; border.width:1
                        Text { text:"CAN'T GET THE API KEY WORKING?"; x:16*root.scaleUnit; y:12*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,13*root.scaleUnit) }
                        Text { text:"Continue with Core Bridge now. You can enable AI Co-Pilot later from Setup."; x:16*root.scaleUnit; y:38*root.scaleUnit; width:parent.width-390*root.scaleUnit; color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,11*root.scaleUnit); wrapMode:Text.WordWrap }
                        MechanicalButton { anchors.right:parent.right; anchors.rightMargin:12*root.scaleUnit; y:12*root.scaleUnit; width:340*root.scaleUnit; height:84*root.scaleUnit; text:"SWITCH TO CORE BRIDGE"; subtext:"BUTTONS + AUTOMATION"; accent:root.green; labelScale:.62; onClicked:root.switchWizardToCore() }
                    }
                }



                Item {
                    anchors.fill:parent; visible:root.introStep===6
                    Text { text:bridge.setupReady?(bridge.bridgeMode==="CORE"?"SETUP COMPLETE // CORE BRIDGE READY":"SETUP COMPLETE // AI CO-PILOT READY"):"SYSTEM HEALTH"; x:34*root.scaleUnit; y:28*root.scaleUnit; color:bridge.setupReady?root.green:root.amber; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(20,29*root.scaleUnit) }
                    Text { text:bridge.setupReady?"Select ENTER BRIDGE to continue. Missing dependencies limit only their related features.":"AI CO-PILOT REQUIRES A VERIFIED OPENAI API KEY"; x:34*root.scaleUnit; y:78*root.scaleUnit; width:parent.width-68*root.scaleUnit; color:bridge.setupReady?root.whiteText:root.amber; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(12,15*root.scaleUnit); wrapMode:Text.WordWrap }
                    Rectangle { x:34*root.scaleUnit; y:126*root.scaleUnit; width:parent.width-68*root.scaleUnit; height:420*root.scaleUnit; color:"#050b07"; border.color:"#244a30"; border.width:1
                        Repeater { model:bridge.setupPreflightRows
                            Rectangle {
                                x:14*root.scaleUnit; y:(12+index*49)*root.scaleUnit; width:parent.width-28*root.scaleUnit; height:43*root.scaleUnit
                                property color resultColor:modelData.status==="READY"?root.green:((modelData.status==="INFO"||modelData.status==="OPTIONAL"||modelData.status==="WAITING"||modelData.status==="NEEDS ATTENTION")?root.amber:root.red)
                                property bool scanHot:root.wizardReadinessScanActive && index===root.wizardReadinessScanIndex
                                color:scanHot?Qt.darker(resultColor,3.1):(index%2?"#061008":"#040804")
                                border.color:scanHot?resultColor:"#183220"; border.width:scanHot?Math.max(2,3*root.scaleUnit):1
                                Rectangle { anchors.fill:parent; color:parent.resultColor; opacity:parent.scanHot?.10:0 }
                                Text { text:modelData.label; x:10*root.scaleUnit; anchors.verticalCenter:parent.verticalCenter; width:parent.width*.31; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(10,12*root.scaleUnit); elide:Text.ElideRight }
                                Text { text:modelData.status; x:parent.width*.33; anchors.verticalCenter:parent.verticalCenter; width:parent.width*.18; color:parent.resultColor; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,12*root.scaleUnit) }
                                Text { text:modelData.detail; x:parent.width*.51; anchors.verticalCenter:parent.verticalCenter; width:parent.width*.47; color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(10,11*root.scaleUnit); elide:Text.ElideRight }
                            }
                        }
                    }
                    Rectangle {
                        x:34*root.scaleUnit; y:570*root.scaleUnit; width:parent.width-68*root.scaleUnit; height:112*root.scaleUnit
                        color:"#061008"; border.color:bridge.setupReady?root.green:root.amber; border.width:2
                        Text { text:bridge.setupReady?"READY // ENTER BRIDGE":"API KEY REQUIRED"; x:16*root.scaleUnit; y:14*root.scaleUnit; color:bridge.setupReady?root.green:root.amber; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(12,16*root.scaleUnit) }
                        Text { text:bridge.setupReady?(bridge.setupLimited?"Setup is complete. Items marked NEEDS ATTENTION disable only the affected features. Select ENTER BRIDGE below to continue.":"Setup is complete. Select ENTER BRIDGE below to continue. The Tutorial remains available from the main Bridge."):"Go Back to AI Co-Pilot and verify the OpenAI API key, or switch to Core Bridge and continue without AI."; x:16*root.scaleUnit; y:48*root.scaleUnit; width:parent.width-32*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.pixelSize:Math.max(10,13*root.scaleUnit); wrapMode:Text.WordWrap }
                    }
                }

                // Wizard pages remain interactive while the guide is speaking. Selection
                // changes update the highlighted controls without cancelling narration;
                // only Back/Next own narration interruption and page changes.
                Rectangle {
                    z:810
                    visible:bridge.wizardNarrationActive
                    anchors.right:parent.right; anchors.rightMargin:18*root.scaleUnit
                    anchors.top:parent.top; anchors.topMargin:14*root.scaleUnit
                    width:330*root.scaleUnit; height:34*root.scaleUnit
                    color:"#211b08"; border.color:root.amber; border.width:1
                    Text { anchors.centerIn:parent; text:"BRIEFING IN PROGRESS"; color:root.amber; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,10*root.scaleUnit) }
                }

                Rectangle {
                    id:wizardSpeakingPanel
                    visible: bridge.wizardNarrationActive
                    x:34*root.scaleUnit; y:parent.height-94*root.scaleUnit
                    width:parent.width-68*root.scaleUnit; height:72*root.scaleUnit
                    color:"#2b2105"; border.color:root.amber; border.width:3
                    SequentialAnimation on color {
                        running:bridge.wizardNarrationActive; loops:Animation.Infinite
                        ColorAnimation { to:"#6a5108"; duration:480; easing.type:Easing.InOutQuad }
                        ColorAnimation { to:"#2b2105"; duration:480; easing.type:Easing.InOutQuad }
                    }
                    SequentialAnimation on scale {
                        running:bridge.wizardNarrationActive; loops:Animation.Infinite
                        NumberAnimation { to:1.008; duration:480; easing.type:Easing.InOutQuad }
                        NumberAnimation { to:1.0; duration:480; easing.type:Easing.InOutQuad }
                    }
                    Text { text:bridge.voiceEngineWarming?"AI COMMS INITIALIZING...":"BRIDGE IS SPEAKING..."; x:18*root.scaleUnit; y:10*root.scaleUnit; color:"#ffd25f"; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(14,19*root.scaleUnit) }
                    Text { text:bridge.voiceEngineWarming?"PREPARING BRIDGE VOICE // WELCOME WILL BEGIN AUTOMATICALLY":"PLEASE LISTEN // MORE GUIDANCE IS COMING // NEXT OR BACK WILL INTERRUPT"; x:18*root.scaleUnit; y:40*root.scaleUnit; width:parent.width-36*root.scaleUnit; color:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(10,12*root.scaleUnit); elide:Text.ElideRight }
                }
            }

            Row {
                x:370*root.scaleUnit; y:parent.height-126*root.scaleUnit
                width:parent.width-x-42*root.scaleUnit; height:86*root.scaleUnit; spacing:14*root.scaleUnit
                property int currentPos:root.wizardStepPosition(root.introStep)
                property bool onFinal:root.introStep===6
                MechanicalButton {
                    width:230*root.scaleUnit; height:parent.height
                    text:(root.wizardUpgradeOnly && parent.currentPos===0)?"CANCEL":"BACK"
                    subtext:(root.wizardUpgradeOnly && parent.currentPos===0)?(bridge.bridgeMode==="CORE"?"KEEP CORE BRIDGE":"KEEP AI CO-PILOT"):(parent.currentPos>0?"PREVIOUS STEP":"START")
                    accent:root.muted; labelScale:.82
                    enabled:parent.currentPos>0 || root.wizardUpgradeOnly
                    opacity:enabled?1.0:.45
                    onClicked:{
                        if(root.wizardUpgradeOnly && parent.currentPos===0){
                            bridge.stopWizard();root.introManualOpen=false;root.introSessionDismissed=true;root.wizardUpgradeOnly=false;root.wizardPath=(bridge.bridgeMode==="CORE"?"CORE":"COPILOT");return
                        }
                        var backStep=root.wizardPreviousPhysicalStep(root.introStep)
                        root.introStep=backStep;root.wizardBackendStep=backStep;root.narrateWizardPage(backStep)
                    }
                }
                Item { width:parent.width-230*root.scaleUnit-360*root.scaleUnit-parent.spacing; height:parent.height }
                MechanicalButton {
                    width:360*root.scaleUnit; height:parent.height
                    text:parent.onFinal?"ENTER BRIDGE":"NEXT"
                    subtext:(root.introStep===0 && root.wizardPath.length===0)?"SELECT CORE BRIDGE OR AI CO-PILOT":((root.introStep===0 && bridge.wizardNarrationActive)?"CONTINUE // INTERRUPT BRIEFING":(root.introStep===2 && !bridge.aiApiVerified?"VERIFY API KEY TO CONTINUE":(parent.onFinal?(bridge.setupReady?"SETUP COMPLETE // CONTINUE":"VERIFY API KEY"):(parent.currentPos+2)+" / "+root.wizardSteps.length)))
                    accent:root.green; labelScale:parent.onFinal?.88:.70
                    busyPulse:parent.onFinal && bridge.setupReady
                    enabled: parent.onFinal ? bridge.setupReady : !(root.introStep===0 && root.wizardPath.length===0) && !(root.introStep===2 && !bridge.aiApiVerified)
                    opacity:enabled?1.0:.48
                    onClicked:{
                        if(!parent.onFinal){
                            if(root.introStep===0 && root.wizardPath.length>0) bridge.setSetupValue("bridge_mode",root.wizardPath)
                            if(root.wizardUpgradeOnly && root.introStep===2 && bridge.aiApiVerified) bridge.setSetupValue("bridge_mode","COPILOT")
                            var nextStep=root.wizardNextPhysicalStep(root.introStep)
                            root.introStep=nextStep;root.wizardBackendStep=nextStep;root.narrateWizardPage(nextStep)
                        } else {
                            bridge.stopWizard();bridge.playUiCue("confirm")
                            bridge.markFirstRunSetupCompleted();bridge.setFirstRunSetupEnabled(false)
                            root.introManualOpen=false;root.introSessionDismissed=true;root.startupPreflightSessionDismissed=true;root.wizardUpgradeOnly=false
                        }
                    }
                }
            }
        }
    }



    // v0.30.56 Bridge-native mandatory controller conflict acknowledgement.
    Popup {
        id: controlConflictPopup
        modal: true
        focus: true
        anchors.centerIn: Overlay.overlay
        width: Math.min(760*root.scaleUnit, root.width-80*root.scaleUnit)
        height: 390*root.scaleUnit
        padding: 0
        closePolicy: Popup.NoAutoClose
        visible: bridge.controlConflictModalActive
        onOpened: bridge.playUiCue("warn")
        background: Rectangle {
            color: "#100807"
            border.color: root.red
            border.width: 3
        }
        contentItem: Item {
            Rectangle { x:0; y:0; width:parent.width; height:58*root.scaleUnit; color:"#2b0b09"; border.color:root.red; border.width:1 }
            Text {
                x:22*root.scaleUnit; y:0; width:parent.width-44*root.scaleUnit; height:58*root.scaleUnit
                verticalAlignment:Text.AlignVCenter
                text:"⚠  ELITE DANGEROUS CONTROL CONFLICT"
                color:root.red; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(16,22*root.scaleUnit)
            }
            Text {
                x:28*root.scaleUnit; y:82*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:46*root.scaleUnit
                text:"THIS HOTAS CONTROL IS ALREADY ASSIGNED IN ELITE DANGEROUS."
                color:root.whiteText; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(15,18*root.scaleUnit)
                wrapMode:Text.WordWrap
            }
            Text {
                x:28*root.scaleUnit; y:139*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:105*root.scaleUnit
                text:"BRIDGE COMMAND  //  "+bridge.controlConflictModalCommand+"\nHOTAS CONTROL   //  "+bridge.controlConflictModalControl+"\nELITE ASSIGNMENT //  "+bridge.controlConflictModalElite
                color:root.amber; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(14,17*root.scaleUnit)
                lineHeight:1.38; wrapMode:Text.WordWrap
            }
            Text {
                x:28*root.scaleUnit; y:253*root.scaleUnit; width:parent.width-56*root.scaleUnit; height:42*root.scaleUnit
                text:"BOTH ELITE DANGEROUS AND ELITE AI BRIDGE MAY RESPOND TO THIS BUTTON. THE BRIDGE ROW WILL REMAIN RED UNTIL THE DUPLICATE ASSIGNMENT IS REMOVED."
                color:root.muted; font.family:"Consolas"; font.pixelSize:Math.max(12,15*root.scaleUnit); wrapMode:Text.WordWrap
            }
            Rectangle {
                id:ackButton
                width:220*root.scaleUnit; height:52*root.scaleUnit
                anchors.horizontalCenter:parent.horizontalCenter; y:315*root.scaleUnit
                property bool hovered:ackMouse.containsMouse
                property bool pressed:ackMouse.pressed
                color:pressed?"#184c32":(hovered?"#103a27":"#092016")
                border.color:hovered?root.green2:root.green; border.width:hovered?2:1
                Text { anchors.centerIn:parent; text:"ACKNOWLEDGE"; color:parent.hovered?root.green2:root.green; font.family:"Consolas"; font.bold:true; font.pixelSize:Math.max(13,16*root.scaleUnit) }
                MouseArea {
                    id:ackMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
                    onClicked:bridge.acknowledgeControlConflict()
                }
            }
        }
    }

}
