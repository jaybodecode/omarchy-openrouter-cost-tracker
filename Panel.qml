import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "openrouter.bar"
  ipcTarget: "openrouter.bar"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property color fg: barIdentity && barIdentity.bar ? barIdentity.bar.barForeground : Color.foreground
  // Stock panels (network/weather) render text with the bar's font family so
  // the panel typography matches the bar it anchors to.
  readonly property string panelFont: barIdentity && barIdentity.bar ? barIdentity.bar.fontFamily : Style.font.family

  // ---- pill properties (read by BarWidget.qml)
  property real pillRemaining: -1
  property real pillTotal: 0
  property real pillUsage: -1
  property bool spendShow: true
  property real spendBase: 0
  property real spendBaseAt: 0
  property bool starPromptDone: false

  readonly property string repoUrl: "https://github.com/jaybodecode/omarchy-openrouter-cost-tracker"
  // Keep in sync with "version" in manifest.json
  readonly property string pluginVersion: "1.2.0"

  readonly property real pillSpend: pillUsage >= 0 ? Math.max(0, pillUsage - spendBase) : -1
  readonly property string pillLabel: pillRemaining < 0 ? ""
    : (spendShow && pillSpend >= 0 ? "$" + pillSpend.toFixed(2) : "")
  // Hover glance reveals the other metric regardless of spendShow — the
  // toggle only controls the persistent pill text, never the hover peek.
  readonly property string pillGlance: {
    agoTick
    if (pillRemaining < 0) return ""
    if (spendShow) return "$" + pillRemaining.toFixed(2) + " left"
    return "$" + (pillSpend >= 0 ? pillSpend.toFixed(2) : (Number(pillUsage) || 0).toFixed(2)) + " spent"
  }
  readonly property bool pillLow: (pillRemaining >= 0 && pillTotal > 0 && pillRemaining < pillTotal * 0.1)
    || anyKeyNearLimit
  // Full themed tooltip content; shown via PanelToolTip on the pill button.
  readonly property string pillTooltip: {
    agoTick
    if (pillRemaining < 0) return "OpenRouter — open to configure"
    var t = "OpenRouter balance: $" + pillRemaining.toFixed(2)
    if (pillSpend >= 0) {
      t += "\nSpent " + (spendBaseAt > 0
        ? "$" + pillSpend.toFixed(2) + " in the last " + fmtDuration(spendBaseAt)
          + " (since " + Qt.formatDateTime(new Date(spendBaseAt * 1000), "ddd MMM d, hh:mm") + ")"
        : "all-time: $" + pillSpend.toFixed(2))
    }
    t += "\n" + agoLabel
    return t
  }

  property FileView cacheFile: FileView {
    path: Quickshell.env("HOME") + "/.local/state/openrouter-bar/cache.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyCache(text())
    onLoadFailed: { root.pillRemaining = -1; root.pillTotal = 0; root.pillUsage = -1 }
  }

  function applyCache(raw) {
    try {
      var data = JSON.parse(String(raw || "{}"))
      pillTotal = Number(data.total_credits) || 0
      var usage = Number(data.total_usage) || 0
      pillUsage = data.total_usage !== undefined ? usage : -1
      pillRemaining = data.total_credits !== undefined ? pillTotal - usage : -1
    } catch (e) {
      pillRemaining = -1
      pillUsage = -1
    }
  }

  // ------------------------------------------------------------- state
  // views: loading | setup | list | create | edit | delete | reveal | settings
  property string view: "loading"
  property var status: null
  property var pins: []
  property var editingKey: null
  property string revealKeyText: ""
  property string banner: ""
  property bool bannerError: false
  property bool busy: false
  property string busyText: ""
  property real fetchedAt: 0
  property bool showAllToggle: false

  readonly property var keys: status && status.keys ? status.keys : []
  readonly property var pinnedKeys: keys.filter(function(k) { return pins.indexOf(k.hash) !== -1 })
  readonly property var otherKeys: keys.filter(function(k) { return pins.indexOf(k.hash) === -1 })
  readonly property real remaining: status ? (Number(status.total_credits) || 0) - (Number(status.total_usage) || 0) : -1
  // True when any capped key is at >= 90% of its limit. Fixed caps
  // (limit_reset never) compare lifetime `usage`; period caps compare the
  // API's per-period field (usage_daily/usage_weekly/usage_monthly). Drives
  // the red pill together with low balance.
  function keyUsageRatio(k) {
    var lim = Number(k.limit) || 0
    if (lim <= 0) return 0
    var reset = k.limit_reset
    var used
    if (reset === "daily") used = Number(k.usage_daily)
    else if (reset === "weekly") used = Number(k.usage_weekly)
    else if (reset === "monthly") used = Number(k.usage_monthly)
    else used = Number(k.usage) // fixed cap: lifetime usage is the measure
    if (isNaN(used)) used = 0
    return used / lim
  }
  readonly property bool anyKeyNearLimit: {
    var ks = status && status.keys ? status.keys : []
    for (var i = 0; i < ks.length; i++) {
      if (keyUsageRatio(ks[i]) >= 0.9) return true
    }
    return false
  }
  readonly property string agoLabel: { agoTick; return fmtAgo() }

  function fmtAgo() {
    if (fetchedAt <= 0) return ""
    var s = Math.max(0, Math.floor((Date.now() / 1000) - fetchedAt))
    if (s < 5) return "updated just now"
    if (s < 60) return "updated " + s + "s ago"
    return "updated " + Math.floor(s / 60) + "m ago"
  }

  // "5h 12m" / "2d 3h" style elapsed time, re-evaluated by agoTick.
  function fmtDuration(sinceTs) {
    if (sinceTs <= 0) return ""
    var s = Math.max(0, Math.floor((Date.now() / 1000) - sinceTs))
    if (s < 60) return s + "s"
    var m = Math.floor(s / 60)
    if (m < 60) return m + "m"
    var h = Math.floor(m / 60)
    if (h < 24) return (m % 60) > 0 ? h + "h " + (m % 60) + "m" : h + "h"
    var d = Math.floor(h / 24)
    return (h % 24) > 0 ? d + "d " + (h % 24) + "h" : d + "d"
  }

  // ------------------------------------------------------------- lifecycle
  // True until the first background fetch of the session completes; gates
  // the one-time star notification so manual refreshes never trigger it.
  property bool firstFetchOfSession: true

  // Delayed startup fetch: give the desktop a few seconds to settle after
  // login, then quietly refresh the pill data (helper serves its 30s cache
  // if we are early). No periodic polling — the panel refreshes on open.
  Timer {
    interval: 5000
    running: true
    repeat: false
    onTriggered: root.refresh(false)
  }

  function open() {
    openedFromHotkey = false
    root.controller.show()
    configFile.reload()
    if (!status) view = "loading"
    else goList()
    refresh(true)
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    configFile.reload()
    if (!status) view = "loading"
    else goList()
    refresh(true)
    Qt.callLater(function() {
      if (root.opened && root.bar && "centerHoverRevealSuppressed" in root.bar)
        root.bar.centerHoverRevealSuppressed = true
    })
  }

  function close() {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function goList() {
    view = (status && status.has_key === false) ? "setup" : "list"
  }

  // ------------------------------------------------------------- helper CLI
  property var helperQueue: []
  property var helperCallback: null
  property bool helperBusy: false

  Process {
    id: helperProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleHelper(String(text || ""))
    }
  }

  function callHelper(argv, cb) {
    if (helperBusy) { helperQueue.push({ argv: argv, cb: cb }); return }
    startHelper(argv, cb)
  }

  // Plugin directory (scripts ship inside the plugin folder, so the whole
  // plugin is self-contained after `omarchy plugin add <git-url>`).
  readonly property string pluginDir: {
    var u = Qt.resolvedUrl("Panel.qml").toString()
    return u.substring(7, u.lastIndexOf("/") + 1) // strip "file://" prefix, keep trailing "/"
  }

  function startHelper(argv, cb) {
    helperBusy = true
    helperCallback = cb || null
    helperProc.command = [pluginDir + "openrouter-bar-api"].concat(argv)
    helperProc.running = true
  }

  function handleHelper(rawText) {
    var cb = helperCallback
    helperCallback = null
    helperBusy = false
    var parsed = null
    try { parsed = JSON.parse(String(rawText || "").trim()) } catch (e) { parsed = null }
    if (cb) cb(parsed)
    if (helperQueue.length) {
      var next = helperQueue.shift()
      startHelper(next.argv, next.cb)
    }
  }

  // ------------------------------------------------------------- data flow
  function refresh(force) {
    setBusy(force, force ? "Refreshing…" : "")
    callHelper(force ? ["refresh"] : ["status"], function(out) {
      setBusy(false)
      if (!out) { banner = "Helper error"; bannerError = true; return }
      if (out.error) {
        if (out.error === "auth") { banner = out.message || "Management key rejected"; bannerError = true; view = "setup"; focusField(setupKeyField, true) }
        else { banner = out.message || String(out.error); bannerError = true }
        return
      }
      applyStatus(out)
    })
  }

  function applyStatus(out) {
    var firstData = !status
    status = out
    if (out.fetched_at) fetchedAt = Number(out.fetched_at)
    spendShow = out.spend_show !== false
    spendBase = typeof out.spend_base === "number" ? out.spend_base : 0
    spendBaseAt = Number(out.spend_base_at) || 0
    starPromptDone = out.star_prompt_done === true
    banner = out.stale ? "Stale data (offline?)" : ""
    bannerError = !!out.stale
    if (out.has_key === false) { view = "setup"; focusField(setupKeyField, true); return }
    if (view === "loading") view = "list"
    agoTick++
    // One-time desktop nudge to star the repo, after the first successful
    // fetch of the session (startup path only — never after manual refresh).
    // Clicking it opens the repo and permanently dismisses the prompt.
    if (firstFetchOfSession) {
      firstFetchOfSession = false
      if (!starPromptDone) {
        var helper = pluginDir + "openrouter-bar-api"
        Quickshell.execDetached(["omarchy-notification-send",
          "--app-name", "OpenRouter Cost Manager", "-u", "low",
          "OpenRouter Cost Manager",
          "Find it useful? Click to star the repo ♥",
          "--exec", "bash", "-c",
          helper + " star-done >/dev/null 2>&1; xdg-open " + repoUrl])
      }
    }
  }

  function mutate(argv, cb) {
    setBusy(true, "Working…")
    callHelper(argv, function(out) {
      setBusy(false)
      if (!out || out.error || out.ok !== true) {
        banner = (out && out.message) ? out.message : "Request failed"
        bannerError = true
        return
      }
      banner = ""
      callHelper(["refresh"], function(st) {
        if (st && !st.error) applyStatus(st)
        if (cb) cb(st)
      })
    })
  }

  function setBusy(on, text) {
    busy = on
    busyText = text || ""
  }

  Timer { id: agoTimer; interval: 1000; repeat: true; triggeredOnStart: true; onTriggered: root.agoTick++ }

  Timer {
    id: busyPhraseTimer
    interval: 2800
    running: root.busy
    repeat: true
    onTriggered: busyPhraseSwap.restart()
  }

  SequentialAnimation {
    id: busyPhraseSwap
    PropertyAnimation {
      target: busyPhraseText; property: "opacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.busyPhraseIndex = (root.busyPhraseIndex + 1) % root.busyPhrases.length
    }
    PropertyAnimation {
      target: busyPhraseText; property: "opacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }
  property int agoTick: 0

  // Rotating vibe-coding phrases while busy — same mechanism as the
  // network panel's "Handling packets" hero meta (fade out, swap, in).
  property int busyPhraseIndex: 0
  readonly property var busyPhrases: [
    "Counting tokens",
    "Pricing prompts",
    "Weighing context",
    "Feeding the model",
    "Burning credits",
    "Rounding up receipts",
    "Negotiating with vendors",
    "Sipping context windows",
    "Auditing inference",
    "Trimming hallucinations",
  ]
  readonly property string busyPhrase: busyPhrases[busyPhraseIndex % busyPhrases.length].toUpperCase()

  Timer {
    interval: 1500
    running: true
    onTriggered: configFile.reload()
  }

  // ------------------------------------------------------------- pins config
  property FileView configFile: FileView {
    path: Quickshell.env("HOME") + "/.config/openrouter-bar/config.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var data = JSON.parse(String(text() || "{}"))
        root.pins = Array.isArray(data.pinned_hashes) ? data.pinned_hashes : []
      } catch (e) { root.pins = [] }
    }
    onLoadFailed: root.pins = []
  }

  function writePins(next) {
    callHelper(["pins", next.join(",")], function(out) {
      if (out && out.ok) root.pins = out.pinned_hashes
    })
  }

  // Star prompt dismissal. Opening the repo counts as fulfilled — GitHub
  // cannot verify who starred, so click-to-open hides the card forever.
  function dismissStarPrompt(openRepo) {
    listColumn.starPeek = false
    starPromptDone = true
    callHelper(["star-done"], null)
    if (openRepo) Quickshell.execDetached(["xdg-open", repoUrl])
  }

  // ------------------------------------------------------------- views
  function focusField(f, selectAll) {
    if (!f) return
    Qt.callLater(function() {
      if (f.visible && f.enabled !== false) {
        if (selectAll && typeof f.selectAll === "function") f.selectAll()
        f.forceActiveFocus()
      }
    })
  }

  function handleEscape() {
    if (view === "create" || view === "edit" || view === "delete" || view === "reveal") {
      view = "list"
    } else {
      root.close()
    }
  }

  function startCreate() {
    createName.text = ""
    createLimit.value = 0
    createReset.value = "never"
    banner = ""
    view = "create"
    focusField(createName)
  }

  function startEdit(keyObj) {
    editingKey = keyObj
    banner = ""
    view = "edit"
    focusField(editName)
  }

  function startDelete(keyObj) {
    editingKey = keyObj
    banner = ""
    deleteConfirmField.text = ""
    view = "delete"
    focusField(deleteConfirmField)
  }

  function startReveal(plaintext) {
    revealKeyText = plaintext
    view = "reveal"
  }

  function openSettings() { banner = ""; view = "settings" }

  function setSpendShow(on) {
    callHelper(["spend-show", on ? "1" : "0"], function(out) {
      if (out && out.ok) spendShow = out.spend_show
    })
  }

  function resetSpend() {
    if (!status) return
    setBusy(true, "Resetting…")
    callHelper(["spend-reset", String(Number(status.total_usage) || 0)], function(out) {
      setBusy(false)
      if (out && out.ok) { spendBase = out.spend_base; spendBaseAt = out.spend_base_at }
    })
  }

  function logout() {
    setBusy(true, "Logging out…")
    callHelper(["logout"], function(out) {
      setBusy(false)
      if (out && out.ok) {
        status = null
        pillRemaining = -1
        pillTotal = 0
        pillUsage = -1
        spendBase = 0
        spendBaseAt = 0
        banner = ""
        view = "setup"
        focusField(setupKeyField, true)
      }
    })
  }

  function copyToClipboard(text) {
    clipboardProc.command = ["wl-copy", "--", text]
    clipboardProc.running = true
  }

  Process { id: clipboardProc }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  // ------------------------------------------------------------- popup
  // KeyboardPanel, NOT PopupCard: xdg-popups (PopupCard) never receive
  // keyboard focus on Hyprland, so TextFields would be dead (see
  // Ui/KeyboardPanel.qml header). KeyboardPanel primes layer-shell focus
  // (Exclusive → OnDemand) and auto-focuses `focusTarget` on open.
  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.barIdentity
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(400))
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight, Style.space(560))

    // Esc handling: bubbles up from focused TextFields (they don't consume
    // Escape); while the catcher itself has focus it receives all keys.
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.handleEscape()

      Column {
        id: contentColumn
        anchors.fill: parent
        spacing: Style.space(10)

      // ---------- header
      Row {
        width: parent.width
        spacing: Style.space(8)

        Column {
          width: parent.width - Style.space(76)
          spacing: Style.space(1)

          Text {
            text: "OpenRouter Cost Manager"
            color: root.fg
            font.family: root.panelFont
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            text: root.view === "setup" ? "management key required"
              : (root.remaining >= 0 ? "$" + root.remaining.toFixed(2) + " available · " + root.agoLabel : "loading…")
            color: Color.muted
            font.family: root.panelFont
            font.pixelSize: Style.font.caption
          }
        }

        PanelActionButton {
          iconText: "󰑐"
          tooltipText: "Refresh"
          enabled: !root.busy
          onClicked: root.refresh(true)
        }

        PanelActionButton {
          iconText: "󰒓"
          tooltipText: "Settings"
          enabled: !root.busy && root.view === "list" && root.status && root.status.has_key !== false
          onClicked: root.openSettings()
        }

        PanelActionButton {
          iconText: "󰐕"
          tooltipText: "New key"
          enabled: !root.busy && root.view === "list" && root.status && root.status.has_key !== false
          onClicked: root.startCreate()
        }
      }

      PanelSeparator {}

      // ---------- banner (stale / errors)
      Rectangle {
        width: parent.width
        height: root.banner !== "" ? bannerText.implicitHeight + Style.space(14) : 0
        visible: root.banner !== ""
        radius: Style.cornerRadius
        color: Util.alpha(root.bannerError ? Color.urgent : Color.accent, 0.15)

        Text {
          id: bannerText
          anchors.centerIn: parent
          width: parent.width - Style.space(16)
          text: root.banner
          color: root.bannerError ? Color.urgent : Color.accent
          font.family: root.panelFont
          font.pixelSize: Style.font.caption
          wrapMode: Text.WrapAnywhere
        }
      }

      Text {
        id: busyPhraseText
        width: parent.width
        visible: root.busy
        text: root.busyText !== "" && root.busyText !== "Refreshing…" ? root.busyText : root.busyPhrase
        color: Color.muted
        font.family: root.panelFont
        font.pixelSize: Style.font.caption
      }

      // ---------- SETUP (first run: paste management key)
      Column {
        width: parent.width
        spacing: Style.space(8)
        visible: root.view === "setup"

        Text {
          width: parent.width
          text: "Paste an OpenRouter management API key.\nCreate one at openrouter.ai/settings/management-keys — it is stored in your keyring, never on disk."
          color: Color.muted
          font.family: root.panelFont
          font.pixelSize: Style.font.caption
          wrapMode: Text.WrapAnywhere
        }

        TextField {
          id: setupKeyField
          width: parent.width
          password: true
          placeholderText: "sk-or-…management key…"
          enabled: !root.busy
          onVisibleChanged: if (visible) root.focusField(setupKeyField)
        }

        Row {
          spacing: Style.space(8)

          Button {
            text: "Save key"
            enabled: !root.busy && setupKeyField.text.trim().length > 10
            onClicked: popup.saveSetupKey()
          }

          Button {
            text: "Close"
            onClicked: root.close()
          }
        }
      }

      // ---------- LIST
      Column {
        id: listColumn
        width: parent.width
        spacing: Style.space(6)
        visible: root.view === "list"

        // ---- Hero: logo · title · big remaining balance (network/weather
        // hero treatment: bar font, bold title, oversized read-out).
        Item {
          width: parent.width
          implicitHeight: heroLogo.implicitHeight + heroMetaText.implicitHeight + Style.space(4)

          Image {
            id: heroLogoSource
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.font.display * 1.4
            height: width
            source: root.pluginDir + "assets/openrouter.svg"
            fillMode: Image.PreserveAspectFit
            sourceSize.width: Math.round(width * 4)
            sourceSize.height: Math.round(height * 4)
            asynchronous: true
            visible: false
            layer.enabled: true
          }

          MultiEffect {
            id: heroLogo
            anchors.fill: heroLogoSource
            source: heroLogoSource
            colorization: 1.0
            colorizationColor: root.pillLow ? Color.urgent : root.fg
          }

          Column {
            anchors.left: heroLogo.right
            anchors.leftMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: "OpenRouter"
              color: root.fg
              font.family: root.panelFont
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              // Uppercase status meta, like the network hero: rotating
              // phrases while busy, data age otherwise.
              text: root.busy ? root.busyPhrase : (root.agoLabel !== "" ? root.agoLabel.toUpperCase() : "")
              color: Qt.darker(root.fg, 1.4)
              font.family: root.panelFont
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
            }
          }

          Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            // Hero read-out: remaining balance, deliberately oversized like
            // the weather panel's temperature.
            text: root.pillRemaining >= 0 ? "$" + root.pillRemaining.toFixed(2) : "—"
            color: root.pillLow ? Color.urgent : root.fg
            font.family: root.panelFont
            font.pixelSize: 28
            font.bold: true
          }
        }

        // One-time "star the repo" card. Appears a few seconds after the
        // panel opens, and disappears forever once clicked/dismissed
        // (star_prompt_done persists in config.json via the helper).
        property bool starPeek: false
        Timer {
          interval: 5000
          running: root.opened && !root.starPromptDone
          repeat: false
          onTriggered: listColumn.starPeek = true
        }

        Rectangle {
          width: parent.width
          visible: root.view === "list" && listColumn.starPeek && !root.starPromptDone
          color: Util.alpha(Color.accent, 0.12)
          radius: Style.cornerRadius
          height: starColumn.implicitHeight + Style.space(12)

          Column {
            id: starColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(6)
            spacing: Style.space(4)

            Row {
              width: parent.width
              spacing: Style.space(4)

              Text {
                width: parent.width - Style.space(24)
                text: "Find OpenRouter Cost Manager useful?"
                color: root.fg
                font.family: root.panelFont
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
              }

              PanelActionButton {
                iconText: "󰅂"
                tooltipText: "Dismiss"
                onClicked: root.dismissStarPrompt(false)
              }
            }

            Text {
              width: parent.width
              text: "Star it on GitHub to support development ♥"
              color: Color.muted
              font.family: root.panelFont
              font.pixelSize: Style.font.caption
            }

            Row {
              spacing: Style.space(8)

              Button {
                text: "Star on GitHub"
                onClicked: root.dismissStarPrompt(true)
              }

              Button {
                text: "Not now"
                bordered: true
                onClicked: root.dismissStarPrompt(false)
              }
            }
          }
        }

        PanelSectionHeader {
          width: parent.width
          text: "Pinned keys"
          color: Color.muted
          visible: root.pinnedKeys.length > 0
        }

        Repeater {
          model: root.pinnedKeys
          delegate: KeyRow {
            width: parent.width
            keyData: modelData
          }
        }

        Text {
          visible: root.showAllToggle || root.pinnedKeys.length === 0
          width: parent.width
          text: "Open API Keys management in Browser"
          color: keysLinkHover.containsMouse ? Color.accent : Color.muted
          font.underline: true
          font.family: root.panelFont
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle

          MouseArea {
            id: keysLinkHover
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Quickshell.execDetached(["xdg-open", "https://openrouter.ai/workspaces/default/keys"])
          }
        }

        PanelSectionHeader {
          width: parent.width
          text: "Other keys (" + root.otherKeys.length + ")"
          color: Color.muted
          visible: root.pinnedKeys.length > 0 && root.showAllToggle
        }

        Repeater {
          model: root.showAllToggle || root.pinnedKeys.length === 0 ? root.otherKeys : []
          delegate: KeyRow {
            width: parent.width
            keyData: modelData
          }
        }

        Button {
          visible: root.pinnedKeys.length > 0 && root.otherKeys.length > 0
          text: root.showAllToggle ? "Hide other keys" : "Show other keys (" + root.otherKeys.length + ")"
          leftAlign: true
          bordered: true
          onClicked: root.showAllToggle = !root.showAllToggle
        }

        Text {
          width: parent.width
          visible: root.keys.length === 0
          text: "No API keys yet. Create one to get started."
          color: Color.muted
          font.family: root.panelFont
          font.pixelSize: Style.font.caption
        }
      }

      // ---------- CREATE
      Column {
        width: parent.width
        spacing: Style.space(8)
        visible: root.view === "create"

        PanelSectionHeader { width: parent.width; text: "Create API key"; color: Color.muted }

        TextField {
          id: createName
          width: parent.width
          placeholderText: "key name (e.g. my-project)"
          enabled: !root.busy
          onVisibleChanged: if (visible) root.focusField(createName)
        }

        Text {
          text: "Credit limit, $ (0 = unlimited)"
          color: Color.muted
          font.pixelSize: Style.font.caption
          font.family: root.panelFont
        }

        Row {
          spacing: Style.space(8)
          NumberField {
            id: createLimit
            from: 0
            to: 100000
            value: 0
            enabled: !root.busy
          }
        }

        Text {
          text: "Limit resets"
          color: Color.muted
          font.pixelSize: Style.font.caption
          font.family: root.panelFont
        }

        Dropdown {
          id: createReset
          options: [
            { label: "never", value: "never" },
            { label: "daily", value: "daily" },
            { label: "weekly", value: "weekly" },
            { label: "monthly", value: "monthly" }
          ]
          value: "never"
          enabled: !root.busy
          onChanged: function(v) { createReset.value = v }
        }

        Row {
          spacing: Style.space(8)

          Button {
            text: "Create"
            enabled: !root.busy && createName.text.trim() !== ""
            onClicked: popup.submitCreate()
          }

          Button {
            text: "Cancel"
            enabled: !root.busy
            onClicked: root.goList()
          }
        }
      }

      // ---------- EDIT
      Column {
        width: parent.width
        spacing: Style.space(8)
        visible: root.view === "edit"

        PanelSectionHeader { width: parent.width; text: "Edit key"; color: Color.muted }

        Text {
          text: root.editingKey ? root.editingKey.name : ""
          color: root.fg
          font.pixelSize: Style.font.body
          font.family: root.panelFont
          font.bold: true
        }

        TextField {
          id: editName
          width: parent.width
          text: root.editingKey ? root.editingKey.name : ""
          enabled: !root.busy
          onVisibleChanged: if (visible) root.focusField(editName)
        }

        Text {
          text: "Credit limit, $ (0 = unlimited)"
          color: Color.muted
          font.pixelSize: Style.font.caption
          font.family: root.panelFont
        }

        Row {
          spacing: Style.space(8)
          NumberField {
            id: editLimit
            from: 0
            to: 100000
            value: root.editingKey ? Math.round(Number(root.editingKey.limit) || 0) : 0
            enabled: !root.busy
          }
          Text {
            text: "spent $" + (root.editingKey ? Number(root.editingKey.usage).toFixed(2) : "0.00")
            color: Color.muted
            font.pixelSize: Style.font.caption
            font.family: root.panelFont
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Text {
          text: "Limit resets"
          color: Color.muted
          font.pixelSize: Style.font.caption
          font.family: root.panelFont
        }

        Dropdown {
          id: editReset
          options: [
            { label: "never", value: "never" },
            { label: "daily", value: "daily" },
            { label: "weekly", value: "weekly" },
            { label: "monthly", value: "monthly" }
          ]
          value: root.editingKey ? (root.editingKey.limit_reset || "never") : "never"
          enabled: !root.busy
          onChanged: function(v) { editReset.value = v }
        }

        Row {
          spacing: Style.space(8)

          Button {
            text: "Save"
            enabled: !root.busy && editName.text.trim() !== ""
            onClicked: popup.submitEdit()
          }

          Button {
            text: "Cancel"
            enabled: !root.busy
            onClicked: root.goList()
          }
        }
      }

      // ---------- DELETE (type the key name to confirm)
      Column {
        width: parent.width
        spacing: Style.space(8)
        visible: root.view === "delete"

        PanelSectionHeader {
          width: parent.width
          text: "Delete key"
          color: Color.urgent
        }

        Text {
          width: parent.width
          text: root.editingKey ? "This permanently deletes “" + root.editingKey.name + "”. Apps using it will stop working."
            : ""
          color: root.fg
          font.family: root.panelFont
          font.pixelSize: Style.font.caption
          wrapMode: Text.WrapAnywhere
        }

        Text {
          width: parent.width
          text: root.editingKey ? "Type “" + root.editingKey.name + "” to confirm:"
            : ""
          color: Color.muted
          font.family: root.panelFont
          font.pixelSize: Style.font.caption
        }

        TextField {
          id: deleteConfirmField
          width: parent.width
          placeholderText: root.editingKey ? root.editingKey.name : ""
          enabled: !root.busy
          onVisibleChanged: if (visible) root.focusField(deleteConfirmField)
        }

        Row {
          spacing: Style.space(8)

          Button {
            text: "Delete forever"
            enabled: !root.busy && root.editingKey !== null && deleteConfirmField.text === root.editingKey.name
            foreground: Color.urgent
            onClicked: popup.submitDelete()
          }

          Button {
            text: "Cancel"
            enabled: !root.busy
            onClicked: root.goList()
          }
        }
      }

      // ---------- REVEAL (plaintext key shown once)
      Column {
        width: parent.width
        spacing: Style.space(8)
        visible: root.view === "reveal"

        PanelSectionHeader { width: parent.width; text: "Key created"; color: Color.muted }

        Text {
          width: parent.width
          text: "Copy it now — it cannot be shown again."
          color: Color.urgent
          font.family: root.panelFont
          font.pixelSize: Style.font.caption
          wrapMode: Text.WrapAnywhere
        }

        Rectangle {
          width: parent.width
          height: revealText.implicitHeight + Style.space(12)
          radius: Style.cornerRadius
          color: Util.alpha(Color.foreground, 0.06)

          Text {
            id: revealText
            anchors.centerIn: parent
            width: parent.width - Style.space(12)
            text: root.revealKeyText
            color: root.fg
            font.family: root.panelFont
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
            wrapMode: Text.NoWrap
          }
        }

        Row {
          spacing: Style.space(8)

          Button {
            text: "Copy"
            onClicked: root.copyToClipboard(root.revealKeyText)
          }

          Button {
            text: "Done"
            onClicked: root.goList()
          }
        }
      }

      // ---------- settings
      Column {
        visible: root.view === "settings"
        width: parent.width
        spacing: Style.space(10)

        PanelSectionHeader { width: parent.width; text: "Settings"; color: Color.muted }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Column {
            width: parent.width - Style.space(64)
            spacing: Style.space(2)

            Text {
              text: "Show spend since reset in bar"
              color: root.fg
              font.family: root.panelFont
              font.pixelSize: Style.font.body
            }

            Text {
              text: "When off, the pill shows just the OR logo — no amounts are shown in the bar at all."
              color: Color.muted
              font.family: root.panelFont
              font.pixelSize: Style.font.caption
              wrapMode: Text.WrapAnywhere
              width: parent.width
            }
          }

          ToggleSwitch {
            anchors.verticalCenter: parent.verticalCenter
            checked: root.spendShow
            interactive: !root.busy
            onToggled: root.setSpendShow(!checked)
          }
        }

        Rectangle { width: parent.width; height: 1; color: Color.popups.border }

        Text {
          text: root.spendBaseAt > 0
            ? "Counting since " + Qt.formatDateTime(new Date(root.spendBaseAt * 1000), "ddd MMM d, hh:mm") + " (" + root.fmtDuration(root.spendBaseAt) + " ago) · $" + Math.max(0, (Number(root.status && root.status.total_usage) || 0) - root.spendBase).toFixed(2) + " since reset"
            : "Counting all-time spend (no reset yet)"
          color: Color.muted
          font.family: root.panelFont
          font.pixelSize: Style.font.caption
          wrapMode: Text.WrapAnywhere
          width: parent.width
        }

        Text {
          text: "Resetting is local only — nothing changes on your OpenRouter account. Total account spend: $" + (Number(root.status && root.status.total_usage) || 0).toFixed(2)
          color: Color.muted
          font.family: root.panelFont
          font.pixelSize: Style.font.caption
          wrapMode: Text.WrapAnywhere
          width: parent.width
        }

        Button {
          text: "Reset spend counter to zero"
          enabled: !root.busy && root.status && root.status.has_key !== false
          onClicked: root.resetSpend()
        }

        PanelSeparator {}

        Text {
          text: "Logging out removes the management key from this machine's system keyring (vault) — it is not kept anywhere on disk. Your keys on OpenRouter are untouched; you can log back in anytime."
          color: Color.muted
          font.family: root.panelFont
          font.pixelSize: Style.font.caption
          wrapMode: Text.WrapAnywhere
          width: parent.width
        }

        Button {
          text: "Log out"
          enabled: !root.busy
          onClicked: root.logout()
        }

        Row {
          spacing: Style.space(8)

          Button {
            text: "Back"
            enabled: !root.busy
            onClicked: root.goList()
          }
        }

        PanelSeparator {}

        // ---------- about
        Column {
          width: parent.width
          spacing: Style.space(4)

          Text {
            text: "OpenRouter Cost Manager v" + root.pluginVersion
            color: root.fg
            font.family: root.panelFont
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            text: "OpenRouter logo © OpenRouter, used to identify the service. This plugin is unofficial and not affiliated with OpenRouter."
            color: Color.muted
            font.family: root.panelFont
            font.pixelSize: Style.font.caption
            wrapMode: Text.WrapAnywhere
          }

          Row {
            spacing: Style.space(8)

            Button {
              text: "GitHub repository"
              onClicked: Quickshell.execDetached(["xdg-open", root.repoUrl])
            }

            Button {
              text: root.starPromptDone ? "Starred ♥" : "Star this project"
              enabled: !root.starPromptDone
              onClicked: root.dismissStarPrompt(true)
            }
          }
        }
      }

      // ---------- loading
      Text {
        visible: root.view === "loading" && !root.busy
        width: parent.width
        text: "Loading…"
        color: Color.muted
        font.family: root.panelFont
        font.pixelSize: Style.font.caption
      }
      }
    }

    // ----------------------------------------------------------- handlers
    function saveSetupKey() {
      var v = setupKeyField.text.trim()
      if (v === "") return
      setBusy(true, "Validating key…")
      callHelper(["set-key", v], function(out) {
        setBusy(false)
        if (!out || out.error || out.ok !== true) {
          banner = (out && out.message) ? out.message : "Key rejected"
          bannerError = true
          return
        }
        banner = ""
        setupKeyField.text = ""
        root.refresh(true)
      })
    }

    function submitCreate() {
      var name = createName.text.trim()
      var limit = createLimit.value > 0 ? createLimit.value : null
      var reset = createReset.value
      setBusy(true, "Creating key…")
      var args = ["create", name, limit !== null ? String(limit) : "-", reset]
      callHelper(args, function(out) {
        setBusy(false)
        if (!out || out.error || out.ok !== true) {
          banner = (out && out.message) ? out.message : "Create failed"
          bannerError = true
          return
        }
        banner = ""
        startReveal(out.key || "")
        callHelper(["refresh"], function(st) { if (st && !st.error) applyStatus(st) })
      })
    }

    function submitEdit() {
      if (!editingKey) return
      var h = editingKey.hash
      var name = editName.text.trim()
      var limit = editLimit.value > 0 ? editLimit.value : null
      var reset = editReset.value
      setBusy(true, "Saving…")
      var args = ["update", h, "--name", name]
      if (limit !== null) args = args.concat(["--limit", String(limit), "--reset", reset])
      callHelper(args, function(out) {
        setBusy(false)
        if (!out || out.error || out.ok !== true) {
          banner = (out && out.message) ? out.message : "Update failed"
          bannerError = true
          return
        }
        banner = ""
        goList()
        callHelper(["refresh"], function(st) { if (st && !st.error) applyStatus(st) })
      })
    }

    function submitDelete() {
      if (!editingKey) return
      var h = editingKey.hash
      setBusy(true, "Deleting…")
      callHelper(["delete", h], function(out) {
        setBusy(false)
        if (!out || out.error || out.ok !== true) {
          banner = (out && out.message) ? out.message : "Delete failed"
          bannerError = true
          return
        }
        banner = ""
        editingKey = null
        // Optimistic local removal: drop the key from the list and pins
        // right away; the forced refresh below then confirms server state.
        if (root.status && root.status.keys) {
          var s = JSON.parse(JSON.stringify(root.status))
          s.keys = s.keys.filter(function(k) { return k.hash !== h })
          root.status = s
        }
        root.pins = root.pins.filter(function(p) { return p !== h })
        goList()
        callHelper(["refresh"], function(st) { if (st && !st.error) applyStatus(st) })
      })
    }
  }

  // ----------------------------------------------------------- key row
  component KeyRow: Rectangle {
    id: rowRoot

    property var keyData: ({})
    property bool pinned: root.pins.indexOf(keyData.hash) !== -1
    readonly property real limitVal: Number(keyData.limit) || 0
    // The usage that matters for this key: lifetime `usage` for fixed caps,
    // the API's per-period field (usage_daily/usage_weekly/usage_monthly)
    // for keys whose limit resets. Falls back to lifetime usage if the
    // period field is missing.
    readonly property bool periodCap: limitVal > 0 && keyData.limit_reset && keyData.limit_reset !== "never"
    readonly property bool lifetimeCap: limitVal > 0 && !periodCap
    readonly property real periodUsageVal: {
      var r = keyData.limit_reset
      if (r === "daily") return Number(keyData.usage_daily) || 0
      if (r === "weekly") return Number(keyData.usage_weekly) || 0
      if (r === "monthly") return Number(keyData.usage_monthly) || 0
      return Number(keyData.usage) || 0
    }
    readonly property real usageVal: Number(keyData.usage) || 0
    readonly property real cappedUsageVal: periodCap ? periodUsageVal : usageVal
    readonly property int pctUsed: limitVal > 0 ? Math.round(cappedUsageVal / limitVal * 100) : -1
    readonly property real pct: limitVal > 0 ? Math.min(1, cappedUsageVal / limitVal) : 0
    readonly property bool nearLimit: pctUsed >= 90

    color: Util.alpha(Color.foreground, 0.05)
    radius: Style.cornerRadius
    height: rowColumn.implicitHeight + Style.space(12)
    opacity: keyData.disabled ? 0.55 : 1

    Column {
      id: rowColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(6)
      spacing: Style.space(4)

      Row {
        width: parent.width
        spacing: Style.space(4)

        Text {
          text: rowRoot.pinned ? "󰐃" : "󰋗"
          color: rowRoot.pinned ? Color.accent : Color.muted
          font.family: root.panelFont
          font.pixelSize: Style.font.iconSmall
          anchors.verticalCenter: parent.verticalCenter

          MouseArea {
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            cursorShape: Qt.PointingHandCursor
            onClicked: root.writePins(rowRoot.pinned
              ? root.pins.filter(function(h) { return h !== rowRoot.keyData.hash })
              : root.pins.concat([rowRoot.keyData.hash]))
          }
        }

        Text {
          width: parent.width - Style.space(62)
          text: rowRoot.keyData.name || ""
          color: rowRoot.keyData.disabled ? Color.muted : root.fg
          font.family: root.panelFont
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          anchors.verticalCenter: parent.verticalCenter
        }

        PanelActionButton {
          iconText: "󰏫"
          tooltipText: "Edit"
          onClicked: root.startEdit(rowRoot.keyData)
        }

        PanelActionButton {
          iconText: "󰆴"
          tooltipText: "Delete"
          onClicked: root.startDelete(rowRoot.keyData)
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(4)

        Text {
          text: "$" + rowRoot.cappedUsageVal.toFixed(2)
            + (rowRoot.limitVal > 0
              ? " / $" + rowRoot.limitVal.toFixed(0) + " (" + rowRoot.pctUsed + "% used)"
              : " spent")
          color: rowRoot.nearLimit ? Color.urgent : Color.muted
          font.family: root.panelFont
          font.pixelSize: Style.font.caption
        }

        Text {
          text: rowRoot.keyData.disabled ? "· disabled"
            : (rowRoot.keyData.limit_reset && rowRoot.keyData.limit_reset !== "never" ? "· resets " + rowRoot.keyData.limit_reset
              : (rowRoot.lifetimeCap ? "· capped at $" + rowRoot.limitVal.toFixed(0) : ""))
          color: Color.muted
          font.family: root.panelFont
          font.pixelSize: Style.font.caption
        }
      }

      Rectangle {
        width: parent.width
        height: Style.space(4)
        radius: Style.space(2)
        color: Util.alpha(Color.foreground, 0.08)
        visible: rowRoot.limitVal > 0

        Rectangle {
          width: parent.width * rowRoot.pct
          height: parent.height
          radius: parent.radius
          color: rowRoot.nearLimit ? Color.urgent : Color.accent
        }
      }
    }
  }
}
