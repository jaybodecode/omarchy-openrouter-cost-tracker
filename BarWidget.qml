import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "assets/openrouter-logo.js" as ORLogo

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

  // ---- OpenRouter logo, tinted at runtime to the exact color text widgets
  // use (barForeground / urgent) — identical rendering to the weather pill.
  readonly property color pillFg: root.panel && root.panel.pillLow ? Color.urgent
    : (button.bar ? button.bar.barForeground : Color.foreground)
  readonly property string logoSource: ORLogo.uri(root.pillFg.toString())
  readonly property bool logoOk: logoImage.status === Image.Ready
  readonly property real logoSize: Style.bar.iconCanvas
  readonly property real logoGap: 6

  // WidgetButton (not BarIconButton): auto-sizes to the text like the clock
  // pill; BarIconButton is a fixed square slot that long amounts overflow.
  // The built-in label is hidden; contentRow renders logo + amount.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Width stays constant on hover — the amount never swaps content, so
    // the pill no longer shifts right under the cursor.
    text: root.panel ? root.panel.pillLabel : ""
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 8.75 + (root.panel && root.panel.pillLabel !== "" ? (root.logoSize + root.logoGap) / 2 : root.logoSize / 2)
    verticalPadding: 8.75
    // The content Row sits above the button's internal MouseArea and breaks
    // its hover tracking, so the built-in tooltip path is unreliable here.
    // tooltipText stays empty and our hoverArea below drives the bar's own
    // themed tooltip (same PopupWindow used by stock bar widgets).
    tooltipText: ""

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) root.bar.run("omarchy-notification-send \"$(" + root.pluginDir + "omarchy-openrouter-status)\"")
      else if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }

    foreground: root.pillFg

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
        color: root.pillFg
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

    // Hover driver for the bar tooltip. The content Row sits above the
    // button's internal MouseArea and its containsMouse is unreliable with
    // overlaid children, so hover is tracked here explicitly. NoButton keeps
    // clicks falling through to the button's own MouseArea.
    MouseArea {
      id: hoverArea
      anchors.fill: parent
      acceptedButtons: Qt.NoButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor

      readonly property bool tooltipHovered: containsMouse

      onContainsMouseChanged: {
        if (!root.bar) return
        if (containsMouse) root.bar.showTooltip(hoverArea, root.panel ? root.panel.pillTooltip : "OpenRouter")
        else root.bar.hideTooltip(hoverArea)
      }
      onExited: if (root.bar) root.bar.hideTooltip(hoverArea)
    }
  }
}
