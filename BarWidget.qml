import QtQuick
import QtQuick.Effects
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

  // ---- OpenRouter logo (official glyph from openrouter.ai brand assets,
  // fill stripped so MultiEffect colorizes it to the theme foreground).
  // Falls back to the built-in label when the asset fails to load.
  readonly property string logoSource: Qt.resolvedUrl("assets/openrouter.svg")
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
    // Width driver only (labelVisible false keeps it unpainted): the amount
    // text, so long values size the pill exactly as they did before.
    text: root.panel ? root.panel.pillLabel : ""
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 8.75 + (root.panel && root.panel.pillLabel !== "" ? (root.logoSize + root.logoGap) / 2 : root.logoSize / 2)
    verticalPadding: 8.75
    // The panel is the detail view: shared bar tooltip suppressed, themed
    // PanelToolTip below instead (same pattern as weather/network widgets).
    tooltipText: ""

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

        Image {
          id: logoImage
          anchors.fill: parent
          source: root.logoSource
          fillMode: Image.PreserveAspectFit
          sourceSize: Qt.size(root.logoSize * 4, root.logoSize * 4)
          asynchronous: true
          visible: false
        }

        // Colorize the glyph to the theme foreground (urgent when low),
        // mirroring how the system tray tints symbolic icons.
        MultiEffect {
          anchors.fill: parent
          source: logoImage
          visible: root.logoOk
          colorization: 1.0
          colorizationColor: root.panel && root.panel.pillLow ? Color.urgent
            : (button.bar ? button.bar.barForeground : Color.foreground)
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

    PanelToolTip {
      visible: button.tooltipHovered && root.panel && root.panel.pillTooltip !== ""
      text: root.panel ? root.panel.pillTooltip : ""
      // Top bar → show below the pill; any other position → above it.
      x: (parent.width - implicitWidth) / 2
      y: button.bar && button.bar.position === "top" ? parent.height + 6 : -implicitHeight - 6
    }
  }
}
