import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs
import "skin"
import "shell"
import "pages"

Window {
    id: root
    visible: false
    width: 2560
    height: 1440
    minimumWidth: 1280
    minimumHeight: 720
    color: "#070706"
    title: bridge.labBuild ? "Elite AI Bridge LAB" : "Elite AI Bridge 2.0"
    property bool closeAuthorized: false
    // Universal launch cinematic. It runs before wizard, startup health, or cockpit.
    property bool startupMovieVisible: false // v0.30.35: startup movie disabled during development
    property bool startupMovieEnding: false
    // v0.30.40: overlay remains lazy-created after Bridge startup.
    // It is instantiated only after the pilot explicitly enables it this session.
    property bool overlayRuntimeRequested: false
    property bool overlayPreview: false     // wizard screen 6: show the real overlay on Elite's screen while the pilot picks
    readonly property bool overlayBlocked: String(bridge.eliteOverlayCompatibility || "").indexOf("CAUTION") === 0
    onOverlayBlockedChanged: {
        if (!overlayRuntimeRequested || introVisible) return
        if (overlayBlocked) showDeckNotice("OVERLAY PAUSED", "ELITE IS FULLSCREEN // ELITE: OPTIONS > GRAPHICS > DISPLAY, SET BORDERLESS", "bad")
        else showDeckNotice("OVERLAY BACK ON", "ELITE IS BORDERLESS OR WINDOWED", "ok")
    }

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
    readonly property bool startupPreflightVisible: false   // screen removed in step 27; was: !introVisible && startupPreflightLatched && !startupPreflightSessionDismissed // v0.30.25: optional user-selected startup systems check
    readonly property var firstOrientationPages: [0, 2, 3, 1, 4, 5, 8] // same order as the module column

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
        if (page < 0 || page > 11) return
        currentPage = page
        var workspace = String(bridge.uiWorkspaceHint || "").toLowerCase()
        if (page === 2) {
            if (workspace === "res_finder") combatPage.utilityMode = 1
            else if (workspace === "tactical") combatPage.utilityMode = 0
        } else if (page === 3) {
            if (workspace === "route_finder" || workspace === "best_trade") tradePage.tradeView = 0
            else if (workspace === "loop_setup" || workspace === "trade_loop") tradePage.tradeView = 1
        }
    }

    function uiPageName(page) {
        if (page === 5) return "COMMANDER"
        if (page === 6) return "SETUP > VOICE & AI"
        if (page === 7) return "SETUP > SOUND"
        if (page === 8) return "SETUP > STATUS"
        if (page === 9) return "SETUP > DISPLAY"
        if (page === 10) return "SETUP > CONTROLS"
        if (page === 11) return "SETUP > AUTOMATION"
        var names = ["FLIGHT DECK","NAVIGATION","COMBAT","TRADE","COLONIZATION","COMMANDER","SETUP","SETUP","SETUP","SETUP","SETUP"]
        return (page >= 0 && page < names.length) ? names[page] : "FLIGHT DECK"
    }

    function currentWorkspaceKey() {
        if (currentPage === 2) return combatPage.utilityMode === 1 ? "res_finder" : "tactical"
        if (currentPage === 3) return tradePage.tradeView === 1 ? "loop_setup" : "best_trade"
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
        root.introStep = 8          // wizard v2: the AI add-on run (screens 8..11)
        root.wizardBackendStep = 8
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

    // help page 12 is Flight Deck's own tour (page 0 is the module overview the full tour uses)
    function helpPageIsHere(p) { return p === currentPage || (p === 12 && currentPage === 0) }
    function pageHelpTarget(page, step) {
        if (page === 0) {
            if (step === 0) return nav.guideTarget
            var moduleIndex = step - 1
            return (moduleIndex >= 0 && moduleIndex < nav.moduleRepeater.count) ? nav.moduleRepeater.itemAt(moduleIndex) : nav.guideTarget
        }
        if (page === 1) return step === 0 ? navigationPage.routeTarget : (step === 1 ? navigationPage.destinationTarget : navigationPage.deckTarget)
        if (page === 2) return step === 0 ? combatPage.deckTarget : (step === 1 ? combatPage.viewTarget : combatPage.infoTarget)
        if (page === 3) return [tradePage.viewTarget, tradePage.infoTarget, tradePage.findTarget][Math.max(0, Math.min(2, step))]
        if (page === 4) return step === 0 ? colonizationPage.infoTarget : (step === 1 ? colonizationPage.listTarget : colonizationPage.deckTarget)
        if (page === 5) return [commanderPage.ranksTarget, commanderPage.recordTarget, commanderPage.sessionTarget, commanderPage.shipTarget, commanderPage.cargoTarget, commanderPage.deckTarget][Math.max(0, Math.min(5, step))]
        if (page === 12) return [live.shipTarget, live.logTarget, live.routeTarget, live.deckTarget][Math.max(0, Math.min(3, step))]   // Flight Deck's own tour
        if (page === 6) return [aiVoicePage.voiceTarget, aiVoicePage.hearTarget, aiVoicePage.aiTarget, aiVoicePage.deckTarget][Math.max(0, Math.min(3, step))]
        if (page === 7) return step === 0 ? setupSoundPage.devicesTarget : (step === 1 ? setupSoundPage.levelsTarget : (step === 2 ? setupSoundPage.sfxTarget : setupSoundPage.deckTarget))
        if (page === 8) return step === 0 ? setupStatusPage.checkTarget : (step === 1 ? setupStatusPage.sideTarget : setupStatusPage.deckTarget)
        if (page === 11) return step === 0 ? setupAutomationPage.dockTarget : (step === 1 ? setupAutomationPage.combatTarget : (step === 2 ? setupAutomationPage.aiTarget : setupAutomationPage.deckTarget))
        if (page === 9) return step === 0 ? setupDisplayPage.windowTarget : (step === 1 ? setupDisplayPage.fxTarget : (step === 2 ? setupDisplayPage.overlayTarget : setupDisplayPage.deckTarget))
        if (page === 10) return step === 0 ? setupControlsPage.pttTarget : (step === 1 ? setupControlsPage.commandsTarget : (step === 2 ? setupControlsPage.eliteTarget : setupControlsPage.deckTarget))
        return null
    }

    // First-run audio/runtime state is synchronized only after the backend is
    // actually online. This avoids losing the opening music/narration commands
    // during backend startup.
    function narrateWizardPage(step) {
        // Wizard v2: the screen number travels in the payload (the backend now copies it).
        bridge.narrateWizardStep(step)
    }

    function syncWizardWithBackend() {
        // LAB: hold the wizard (and its voice) until the boot splash has faded.
        // Without this the first screen started talking under the splash.
        if (!bridge.bootSplashDone) return
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
        // wizard v2: refresh what each screen reads
        if (introVisible && bridge.connected) {
            if (introStep === 1) bridge.requestCommand("setup_preflight")
            else if (introStep === 2) bridge.requestCommand("setup_binds")
            else if (introStep === 4) bridge.requestCommand("audio_rescan")
        }
        if (introVisible && !bridge.connected) syncWizardWithBackend()
    }
    Component.onCompleted: { startupPreflightLatched=bridge.startupPreflightEnabled; overlayRuntimeRequested=bridge.gameOverlayEnabled; syncWizardWithBackend(); publishUiContext() }
    Connections {
        target: bridge
        function onBootSplashChanged() { root.syncWizardWithBackend() }
    }
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
        if (!root.firstOrientationActive && bridge.pageHelpActive && !root.helpPageIsHere(bridge.pageHelpPage)) bridge.stopPageHelp()
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

    // Ship art by class (ship-art-categories.md). One original image per class; the CLASS tag says the real class.
    // [art file key, class tag]. Elite's internal names are listed beside the display names.
    readonly property var shipClassTable: ({
        "eagle_mk_ii": ["light_fighter_interceptor", "LIGHT FIGHTER"],
        "imperial_eagle": ["light_fighter_interceptor", "LIGHT FIGHTER"],
        "imperial_courier": ["light_fighter_interceptor", "LIGHT FIGHTER"],
        "viper_mk_iii": ["light_fighter_interceptor", "LIGHT FIGHTER"], "viper": ["light_fighter_interceptor", "LIGHT FIGHTER"],
        "viper_mk_iv": ["light_fighter_interceptor", "LIGHT FIGHTER"], "viper_mkiv": ["light_fighter_interceptor", "LIGHT FIGHTER"],
        "vulture": ["light_fighter_interceptor", "LIGHT FIGHTER"],
        "kestrel_mk_ii": ["light_fighter_interceptor", "LIGHT COMBAT"], "smallcombat01_nx": ["light_fighter_interceptor", "LIGHT COMBAT"], "kestrel": ["light_fighter_interceptor", "LIGHT COMBAT"],
        "sidewinder": ["light_utility_explorer", "LIGHT UTILITY"], "sidewinder_mk_i": ["light_utility_explorer", "LIGHT UTILITY"],
        "adder": ["light_utility_explorer", "LIGHT UTILITY"],
        "hauler": ["light_utility_explorer", "LIGHT UTILITY"],
        "cobra_mk_iii": ["light_utility_explorer", "LIGHT MULTIROLE"],
        "cobra_mk_iv": ["light_utility_explorer", "LIGHT MULTIROLE"],
        "cobra_mk_v": ["light_utility_explorer", "LIGHT MULTIROLE"],
        "diamondback_scout": ["light_utility_explorer", "LIGHT EXPLORER"], "diamondback": ["light_utility_explorer", "LIGHT EXPLORER"],
        "diamondback_explorer": ["light_utility_explorer", "LIGHT EXPLORER"], "diamondbackxl": ["light_utility_explorer", "LIGHT EXPLORER"],
        "dolphin": ["light_utility_explorer", "LIGHT PASSENGER"],
        "asp_explorer": ["medium_multirole", "MEDIUM EXPLORER"],
        "asp_scout": ["medium_multirole", "MEDIUM MULTIROLE"],
        "krait_mk_ii": ["medium_multirole", "MEDIUM MULTIROLE"],
        "krait_phantom": ["medium_multirole", "MEDIUM EXPLORER"], "krait_light": ["medium_multirole", "MEDIUM EXPLORER"],
        "python": ["medium_multirole", "MEDIUM MULTIROLE"],
        "mandalay": ["medium_multirole", "MEDIUM EXPLORER"],
        "corsair": ["medium_multirole", "MEDIUM MULTIROLE"],
        "alliance_challenger": ["medium_combat", "MEDIUM COMBAT"], "typex_3": ["medium_combat", "MEDIUM COMBAT"],
        "alliance_chieftain": ["medium_combat", "MEDIUM COMBAT"], "typex": ["medium_combat", "MEDIUM COMBAT"],
        "alliance_crusader": ["medium_combat", "MEDIUM COMBAT"], "typex_2": ["medium_combat", "MEDIUM COMBAT"],
        "federal_assault_ship": ["medium_combat", "MEDIUM COMBAT"],
        "federal_dropship": ["medium_combat", "MEDIUM COMBAT"],
        "federal_gunship": ["medium_combat", "MEDIUM COMBAT"],
        "fer_de_lance": ["medium_combat", "MEDIUM COMBAT"], "ferdelance": ["medium_combat", "MEDIUM COMBAT"],
        "mamba": ["medium_combat", "MEDIUM COMBAT"],
        "python_mk_ii": ["medium_combat", "MEDIUM COMBAT"], "python_nx": ["medium_combat", "MEDIUM COMBAT"],
        "keelback": ["medium_freighter", "MEDIUM FREIGHTER"], "independant_trader": ["medium_freighter", "MEDIUM FREIGHTER"],
        "type_6_transporter": ["medium_freighter", "MEDIUM FREIGHTER"],
        "type_8_transporter": ["medium_freighter", "MEDIUM FREIGHTER"],
        "type_11_prospector": ["medium_freighter", "MEDIUM MINER"], "lakonminer": ["medium_freighter", "MEDIUM MINER"],
        "lynx_highliner": ["large_passenger_luxury_liner", "MEDIUM PASSENGER"], "lynx": ["large_passenger_luxury_liner", "MEDIUM PASSENGER"],
        "type_7_transporter": ["large_freighter_hauler", "LARGE FREIGHTER"],
        "type_9_heavy": ["large_freighter_hauler", "LARGE FREIGHTER"],
        "imperial_cutter": ["large_freighter_hauler", "LARGE MULTIROLE"],
        "panther_clipper_mk_ii": ["large_freighter_hauler", "LARGE FREIGHTER"], "panthermkii": ["large_freighter_hauler", "LARGE FREIGHTER"],
        "anaconda": ["large_combat", "LARGE MULTIROLE"],
        "federal_corvette": ["large_combat", "LARGE COMBAT"],
        "type_10_defender": ["large_combat", "LARGE COMBAT"], "type9_military": ["large_combat", "LARGE COMBAT"],
        "imperial_clipper": ["large_combat", "LARGE MULTIROLE"],
        "beluga_liner": ["large_passenger_luxury_liner", "LARGE PASSENGER"], "belugaliner": ["large_passenger_luxury_liner", "LARGE PASSENGER"],
        "orca": ["large_passenger_luxury_liner", "LARGE PASSENGER"],
        "caspian_explorer": ["large_passenger_luxury_liner", "HEAVY EXPLORER"], "explorer_nx": ["large_passenger_luxury_liner", "HEAVY EXPLORER"]
    })
    // null when the ship isn't on file (new ship, or not a ship at all)
    function shipClassInfo(shipModelText) {
        var key = normalizeShipArtKey(shipModelText)
        var row = shipClassTable[key]
        if (!row) return null
        var tag = row[1]
        return { art: row[0], tag: tag, size: tag.indexOf("LIGHT") === 0 ? "light" : (tag.indexOf("MEDIUM") === 0 ? "medium" : "large") }
    }
    // "" when there's no art: the page shows the contact scanner instead
    function shipArtSource(shipModelText) {
        var info = shipClassInfo(shipModelText)
        return info ? "assets/ship_art/ship_cat_" + info.art + ".png" : ""
    }
    // what the scanner should say about something with no art: "none" / "nonship" / "unmatched"
    function contactKind(text) {
        var raw = String(text || "").trim()
        if (!raw || raw === "-") return "none"
        if (shipClassInfo(raw)) return "ship"
        var key = normalizeShipArtKey(raw)
        if (/fighter|thargoid|carrier|mega|limpet|escape_pod|black_box|station|orbis|coriolis|ocellus|outpost|srv|scarab|scorpion|rhino|skimmer|installation|settlement|beacon|cyclop|taipan|trident|javelin|lance|condor|gu_97|unknown/.test(key)) return "nonship"
        return "unmatched"
    }
    function niceShipName(text) {
        return String(text || "").replace(/_/g, " ").toUpperCase()
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

    // Retro chassis (build step 3): painted housing, shared header, module column and
    // identity strip, all built from the shared skin parts in qml/skin.
    Binding { target: Theme; property: "s"; value: root.scaleUnit }

    // Short-lived message on the header screen when an unavailable key is pressed.
    property string deckNotice: ""
    property string deckNoticeDetail: ""
    property string deckNoticeLevel: "info"
    function showDeckNotice(title, detail, level) {
        deckNotice = String(title || "").toUpperCase()
        deckNoticeDetail = String(detail || "").toUpperCase()
        deckNoticeLevel = level ? String(level) : "info"
        deckNoticeTimer.restart()
    }
    Timer { id: deckNoticeTimer; interval: 3500; onTriggered: { root.deckNotice = ""; root.deckNoticeDetail = "" } }

    Rectangle {
        anchors.fill: parent
        color: "#2e302a"
        Image {
            anchors.fill: parent
            source: "skin/textures/tex_housing.jpg"
            fillMode: Image.Tile; smooth: true
            sourceSize.width: 1400
        }
        Rectangle { anchors.fill: parent; color: "black"; opacity: 0.18 }
    }

    // Header assembly (every page).
    ChassisHeader {
        id: header
        x: root.m; y: root.m
        width: root.width-root.m*2; height: root.topH
        app: root
        notice: root.deckNotice
        noticeDetail: root.deckNoticeDetail
        noticeLevel: root.deckNoticeLevel
        onUpdatePressed: root.currentPage = 8
        onMasterCautionPressed: {
            // Setup problems are listed on SETUP > SYSTEM. Flight alerts are already on the header screen.
            if (header.setupProblems.length > 0 && !header.shieldsDown && !header.flightAlert) {
                root.currentPage = 8
            }
        }
    }

    // Module column (every page).
    ModuleColumn {
        id: nav
        x: root.m; y: root.m+root.topH+root.gap
        width: root.navW; height: root.height-y-root.m
        app: root
        onModulePicked: (page) => {
            root.currentPage = page
        }
    }

    // Identity readout strip (every page).
    IdentityStrip {
        id: identity
        x: nav.x+nav.width+root.gap; y: nav.y
        width: root.width-x-root.m; height: root.infoH
    }

    // FLIGHT DECK (page 0, formerly Overview).
    FlightDeck {
        id: live
        visible: root.currentPage === 0
        x: identity.x; y: identity.y+identity.height+root.gap
        width: identity.width; height: root.height-y-root.m
        app: root
        onDenied: (title, reason) => root.showDeckNotice(title, reason)
    }

    // NAVIGATION (page 1): route computer, flight plan, set destination, in-system target, route log.
    Navigation {
        id: navigationPage
        objectName: "navigationPage"
        visible: root.currentPage === 1
        x: identity.x; y: identity.y+identity.height+root.gap
        width: identity.width; height: root.height-y-root.m
        app: root
        demo: root.firstOrientationActive && root.currentPage === 1
        onDenied: (title, reason) => root.showDeckNotice(title, reason)
        onNotice: (title, detail, level) => root.showDeckNotice(title, detail, level)
    }


    // COMBAT (page 2): TACTICAL and BOUNTY HUNTING views.
    Combat {
        id: combatPage
        objectName: "combatPage"
        visible: root.currentPage === 2
        x: identity.x; y: identity.y+identity.height+root.gap
        width: identity.width; height: root.height-y-root.m
        app: root
        demo: root.firstOrientationActive && root.currentPage === 2
        onUtilityModeChanged: root.publishUiContext()
        onDenied: (title, reason) => root.showDeckNotice(title, reason)
    }


    // TRADE (page 3): FIND A ROUTE and MY RUN views.
    Trade {
        id: tradePage
        objectName: "tradePage"
        visible: root.currentPage === 3
        x: identity.x; y: identity.y+identity.height+root.gap
        width: identity.width; height: root.height-y-root.m
        app: root
        demo: root.firstOrientationActive && root.currentPage === 3
        onTradeViewChanged: root.publishUiContext()
        onDenied: (title, reason) => root.showDeckNotice(title, reason)
        onNotice: (title, detail, level) => root.showDeckNotice(title, detail, level)
    }

    // COLONIZATION (page 4): THIS PROJECT and MY SITES views.
    Colonization {
        id: colonizationPage
        objectName: "colonizationPage"
        visible: root.currentPage === 4
        x: identity.x; y: identity.y+identity.height+root.gap
        width: identity.width; height: root.height-y-root.m
        app: root
        demo: root.firstOrientationActive && root.currentPage === 4
        onDenied: (title, reason) => root.showDeckNotice(title, reason)
        onNotice: (title, detail, level) => root.showDeckNotice(title, detail, level)
    }


    // COMMANDER (page 5): ranks, ship, career, session, cargo hold.
    Commander {
        id: commanderPage
        objectName: "commanderPage"
        visible: root.currentPage === 5
        x: identity.x; y: identity.y+identity.height+root.gap
        width: identity.width; height: root.height-y-root.m
        app: root
        demo: root.firstOrientationActive && root.currentPage === 5
        onDenied: (title, reason) => root.showDeckNotice(title, reason)
        onNotice: (title, detail, level) => root.showDeckNotice(title, detail, level)
    }


    // Configuration views are nested under SETUP. The old page IDs remain
    // intact so existing automation and AI routing do not need to change.
    Plate {
        id: setupSectionTabs
        visible: root.currentPage === 6 || root.currentPage === 7 || root.currentPage === 8 || root.currentPage === 9 || root.currentPage === 10 || root.currentPage === 11
        x: identity.x; y: identity.y+identity.height+root.gap
        width: identity.width; height: 88*root.scaleUnit
        screwSize: 11*root.scaleUnit
        Text {
            id: setupTabsLabel
            x: 26*root.scaleUnit; anchors.verticalCenter: parent.verticalCenter
            text: "SETUP"; color: Theme.plateText; font.family: Theme.labelFont; font.pixelSize: Math.max(8, 13*root.scaleUnit); font.letterSpacing: 3*root.scaleUnit
        }
        Row {
            x: setupTabsLabel.x + setupTabsLabel.width + 22*root.scaleUnit; y: 9*root.scaleUnit
            width: parent.width - x - 22*root.scaleUnit; height: parent.height - 18*root.scaleUnit
            spacing: 10*root.scaleUnit
            Repeater {
                // tasks in the order a new player meets them (setup-plan.md)
                model: [["STATUS", "START HERE", 8], ["VOICE & AI", "TALK + ASSIST", 6], ["CONTROLS", "KEYS + PUSH TO TALK", 10],
                        ["SOUND", "SPEAKERS + MIC", 7], ["AUTOMATION", "DONE FOR YOU", 11], ["DISPLAY", "SCREEN + OVERLAY", 9]]
                LitButton {
                    width: (parent.width - parent.spacing*5)/6; height: parent.height
                    title: modelData[0]; sub: modelData[1]
                    on: root.currentPage === modelData[2]
                    onActivated: root.currentPage = modelData[2]
                }
            }
        }
    }

    // SETUP > VOICE & AI (page 6): ship voice, what the Bridge hears, what the AI may do.
    SetupVoiceAi {
        id: aiVoicePage
        objectName: "setupVoiceAiPage"
        visible: root.currentPage === 6
        x: identity.x
        y: setupSectionTabs.y + setupSectionTabs.height + root.gap
        width: identity.width
        height: root.height - y - root.m
        app: root
        onDenied: (title, reason) => root.showDeckNotice(title, reason)
        onNotice: (title, detail, level) => root.showDeckNotice(title, detail, level)
    }

    // SETUP > SOUND (page 7): devices, levels, alert sounds.
    SetupSound {
        id: setupSoundPage
        objectName: "setupSoundPage"
        visible: root.currentPage === 7
        x: identity.x
        y: setupSectionTabs.y + setupSectionTabs.height + root.gap
        width: identity.width
        height: root.height - y - root.m
        app: root
        onDenied: (title, reason) => root.showDeckNotice(title, reason)
        onNotice: (title, detail, level) => root.showDeckNotice(title, detail, level)
    }


    // SETUP > CONTROLS (page 10): push to talk, Bridge shortcut keys, Elite keys it needs.
    SetupControls {
        id: setupControlsPage
        objectName: "setupControlsPage"
        visible: root.currentPage === 10
        x: identity.x
        y: setupSectionTabs.y + setupSectionTabs.height + root.gap
        width: identity.width
        height: root.height - y - root.m
        app: root
        onDenied: (title, reason) => root.showDeckNotice(title, reason)
        onNotice: (title, detail, level) => root.showDeckNotice(title, detail, level)
    }


    // In-game overlay (v2, retro skin). Frameless, always on top, click-through.
    // Panels: skin/OverlayPanels.qml. State: bridge.bridgeActivity (main.py), one
    // place for the logic. LEFT / CENTER / RIGHT stack the panels; stale TOP reads as RIGHT.
    Loader {
        id: gameOverlayLoader
        // never over an exclusive-fullscreen Elite: it can pull Elite out of fullscreen or flicker.
        // The setting stays on; the overlay comes back by itself once Elite is borderless or windowed.
        active: (root.overlayRuntimeRequested || root.overlayPreview) && !root.overlayBlocked
        sourceComponent: Component {
            Window {
                id: gameOverlay
                visible: true
                // 2.0.0: the pilot picks the screen (Setup > Display, wizard). The panels fade out
                // while the wizard is open, and while the Bridge window is in front on the same
                // screen, so the overlay never covers the Bridge itself. The window stays up
                // (just empty) so showing and hiding never steals focus from Elite.
                readonly property var scr: Qt.application.screens[Math.max(0, Math.min(Qt.application.screens.length - 1, Number(bridge.gameOverlayScreen)))] || Qt.application.screens[0]
                readonly property bool bridgeInFront: root.active && root.visibility !== Window.Minimized && root.visibility !== Window.Hidden
                readonly property bool sameScreen: Number(bridge.activeMonitorIndex) === Number(bridge.gameOverlayScreen)
                readonly property bool hidePanels: root.overlayPreview ? false : (root.introVisible || (bridgeInFront && sameScreen))
                screen: scr
                property string overlayMode: bridge.gameOverlayMode
                property string overlayPosition: bridge.gameOverlayPosition
                property string overlaySize: bridge.gameOverlaySize
                property real sizeFactor: overlaySize === "SMALL" ? 0.62 : (overlaySize === "LARGE" ? 1.42 : 1.0)
                width: Math.max(10, panels.implicitWidth)
                height: Math.max(10, panels.implicitHeight)
                color: "transparent"
                flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool | Qt.WindowTransparentForInput | Qt.WindowDoesNotAcceptFocus
                x: scr.virtualX + (overlayPosition === "LEFT" ? 46 : (overlayPosition === "CENTER" ? Math.round((scr.width-width)/2) : scr.width-width-46))
                y: scr.virtualY + (overlayPosition === "CENTER" ? 42 : Math.round((scr.height-height)/2))
                OverlayPanels {
                    id: panels
                    opacity: gameOverlay.hidePanels ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    animate: !gameOverlay.hidePanels
                    f: gameOverlay.sizeFactor
                    see: Math.max(0.25, Math.min(1.0, bridge.gameOverlayOpacity / 100.0))
                    showActivity: gameOverlay.overlayMode !== "CHAT"
                    showChat: gameOverlay.overlayMode !== "ACTIVITY"
                    activity: bridge.bridgeActivity
                    title: bridge.bridgeActivityTitle
                    detail: bridge.bridgeActivityDetail
                    rows: bridge.aiCommsRows
                }
            }
        }
    }

    // SETUP > DISPLAY (page 9): this window, screen effects, in-game overlay.
    SetupDisplay {
        id: setupDisplayPage
        objectName: "setupDisplayPage"
        visible: root.currentPage === 9
        x: identity.x
        y: setupSectionTabs.y + setupSectionTabs.height + root.gap
        width: identity.width
        height: root.height - y - root.m
        app: root
        onDenied: (title, reason) => root.showDeckNotice(title, reason)
        onNotice: (title, detail, level) => root.showDeckNotice(title, detail, level)
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
        } }

        Timer {
            id:systemCheckFinishTimer
            interval:1400
            repeat:false
            onTriggered:{setupPage.systemCheckRunning=false;bridge.playUiCue(bridge.setupReady&&!bridge.setupLimited?"confirm":"warn")}
        }

        SetupStatus {
            id: setupStatusPage
            objectName: "setupStatusPage"
            anchors.fill: parent
            app: root
            onDenied: (title, reason) => root.showDeckNotice(title, reason)
            onNotice: (title, detail, level) => root.showDeckNotice(title, detail, level)
        }
    }

    // SETUP > AUTOMATION (page 11): everything the Bridge does on its own.
    SetupAutomation {
        id: setupAutomationPage
        objectName: "setupAutomationPage"
        visible: root.currentPage === 11
        x: identity.x
        y: setupSectionTabs.y + setupSectionTabs.height + root.gap
        width: identity.width
        height: root.height - y - root.m
        app: root
        onDenied: (title, reason) => root.showDeckNotice(title, reason)
        onNotice: (title, detail, level) => root.showDeckNotice(title, detail, level)
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
        visible: bridge.pageHelpActive && (root.helpPageIsHere(bridge.pageHelpPage) || (root.firstOrientationActive && bridge.pageHelpPage===0)) && !root.introVisible
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
                // short targets (a single deck key) put the tag under the box, so it doesn't sit on the deck's own label
                readonly property bool below: helpSpotlight.height < 240*root.scaleUnit
                x: 10*root.scaleUnit; y: below ? parent.height-14*root.scaleUnit : -16*root.scaleUnit
                width: Math.min(420*root.scaleUnit, Math.max(parent.width-20*root.scaleUnit, 320*root.scaleUnit)); height: 30*root.scaleUnit
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

    // (step 27) The v1.0.1 startup pre-flight screen was removed: Setup > Status does that job.

    // FIRST-RUN GUIDED SETUP v2 (shell/SetupWizard.qml). Overlays the cockpit; reopened
    // from SETUP > STATUS (SETUP WIZARD) and SETUP > VOICE & AI (AI add-on only).
    SetupWizard {
        id: firstRunSetupOverlay
        anchors.fill: parent
        z: 5000
        visible: root.introVisible
        app: root
        targets: ({ identity: identity, deck: live.deckTarget, dock: live.dockTarget, cancel: live.cancelTarget, voice: nav.voiceTarget, header: header })
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
