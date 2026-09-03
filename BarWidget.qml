import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "openrouter.bar"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // Shape contract for shell.summon/hide/toggle routing.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
    else if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  // Pill state comes from the panel, which watches the shared cache file
  // the helper writes on every fetch.
  readonly property var panel: panelLoader.item

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // Plugin directory (self-contained: helper scripts ship in the folder).
  readonly property string pluginDir: {
    var u = Qt.resolvedUrl("BarWidget.qml").toString()
    return u.substring(7, u.lastIndexOf("/") + 1) // strip "file://" prefix, keep trailing "/"
  }

  // ---- OpenRouter logo. Qt's MultiEffect colorization proved unreliable
  // for this plugin context (rendered black), so the glyph ships as three
  // pre-tinted variants of the official mark and the right one is chosen by
  // theme luminance — white glyph on dark themes, dark on light, red when
  // any cap/balance is low.
  readonly property color pillFg: root.panel && root.panel.pillLow ? Color.urgent
    : (button.bar ? button.bar.barForeground : Color.foreground)
  readonly property real pillFgLum: 0.299 * pillFg.r + 0.587 * pillFg.g + 0.114 * pillFg.b
  readonly property string logoSource: Qt.resolvedUrl(
    root.panel && root.panel.pillLow ? "assets/openrouter-urgent.svg"
      : (pillFgLum > 0.5 ? "assets/openrouter-ondark.svg" : "assets/openrouter-onlight.svg"))
  readonly property bool logoOk: logoImage.status === Image.Ready
  readonly property real logoSize: Style.bar.iconCanvas
  readonly property real logoGap: 6

  // WidgetButton (not BarIconButton): auto-sizes to the text like the clock
  // pill; BarIconButton is a fixed square slot that long amounts overflow.
  // The built-in label is hidden; contentRow renders logo + amount and the
  // extra horizontal margin reserves room for the logo on the left.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Hover glance (peek the other metric) + width-driving amount, exactly
    // the old WidgetButton.text behavior — now painted by contentRow.
    text: {
      if (!root.panel) return ""
      if (button.tooltipHovered && root.panel.pillGlance !== "") return root.panel.pillGlance
      return root.panel.pillLabel
    }
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 8.75 + (root.panel && root.panel.pillLabel !== "" ? (root.logoSize + root.logoGap) / 2 : root.logoSize / 2)
    verticalPadding: 8.75
    // Multi-line content styled by the bar's own themed tooltip overlay.
    tooltipText: root.panel ? root.panel.pillTooltip : "OpenRouter"

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) root.bar.run("omarchy-notification-send \"$(" + root.pluginDir + "omarchy-openrouter-status)\"")
      else if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }

    foreground: root.panel && root.panel.pillLow ? Color.urgent
      : (button.bar ? button.bar.barForeground : Color.foreground)

    Row {
      id: contentRow
      anchors.centerIn: parent
      spacing: root.logoGap

      Item {
        width: root.logoSize
        height: root.logoSize
        anchors.verticalCenter: parent.verticalCenter
        visible: root.logoOk

        Image {
          id: logoImage
          anchors.fill: parent
          source: root.logoSource
          fillMode: Image.PreserveAspectFit
          sourceSize.width: Math.round(root.logoSize * 4)
          sourceSize.height: Math.round(root.logoSize * 4)
        }
      }

      Text {
        visible: root.panel && root.panel.pillLabel !== ""
        text: root.panel ? root.panel.pillLabel : ""
        color: root.panel && root.panel.pillLow ? Color.urgent
          : (button.bar ? button.bar.barForeground : Color.foreground)
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
        anchors.verticalCenter: parent.verticalCenter

        Behavior on color {
          enabled: !button.bar || button.bar.foregroundAnimationEnabled
          ColorAnimation { duration: 160 }
        }
      }
    }
  }
}
