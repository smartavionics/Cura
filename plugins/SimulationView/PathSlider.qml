// Copyright (c) 2017 Ultimaker B.V.
// Cura is released under the terms of the LGPLv3 or higher.

import QtQuick 2.5
import QtQuick.Controls 1.2
import QtQuick.Layouts 1.1
import QtQuick.Controls.Styles 1.1

import UM 1.0 as UM
import Cura 1.0 as Cura

Item
{
    id: sliderRoot

    // handle properties
    property real handleSize: UM.Theme.getSize("slider_handle").width
    property real handleRadius: handleSize / 2
    property color handleColor: UM.Theme.getColor("slider_handle")
    property color handleActiveColor: UM.Theme.getColor("slider_handle_active")
    property color rangeColor: UM.Theme.getColor("slider_groove_fill")
    property real handleLabelWidth: width

    // track properties
    property real trackThickness: UM.Theme.getSize("slider_groove").width
    property real trackRadius: UM.Theme.getSize("slider_groove_radius").width
    property color trackColor: UM.Theme.getColor("slider_groove")

    // value properties
    property real maximumValue: 100
    property real minimumValue: 0
    property bool roundValues: true
    property real handleValue: maximumValue

    property bool pathsVisible: true
    property bool manuallyChanged: true     // Indicates whether the value was changed manually or during simulation

    function getHandleValueFromSliderHandle()
    {
        return handle.getValue()
    }

    function setHandleValue(value)
    {
        handle.setValue(value)
        updateRangeHandle()
    }

    function updateRangeHandle()
    {
        rangeHandle.width = handle.x - sliderRoot.handleSize
    }

    function normalizeValue(value)
    {
        return Math.min(Math.max(value, sliderRoot.minimumValue), sliderRoot.maximumValue)
    }

    function setHandleLabel(value)
    {
        handle.setHandleLabel(value)
    }

    onWidthChanged : {
        // After a width change, the pixel-position of the handle is out of sync with the property value
        setHandleValue(handleValue)
    }

    // slider track
    Rectangle
    {
        id: track

        width: sliderRoot.width - sliderRoot.handleSize
        height: sliderRoot.trackThickness
        radius: sliderRoot.trackRadius
        anchors.centerIn: sliderRoot
        color: sliderRoot.trackColor
        visible: sliderRoot.pathsVisible
    }

    // Progress indicator
    Item
    {
        id: rangeHandle

        x: handle.width
        height: sliderRoot.handleSize
        width: handle.x - sliderRoot.handleSize
        anchors.verticalCenter: sliderRoot.verticalCenter
        visible: sliderRoot.pathsVisible

        Rectangle
        {
            height: sliderRoot.trackThickness
            width: parent.width + sliderRoot.handleSize
            anchors.centerIn: parent
            radius: sliderRoot.trackRadius
            color: sliderRoot.rangeColor
        }
    }

    // Handle
    Rectangle
    {
        id: handle

        x: sliderRoot.handleSize
        width: sliderRoot.handleSize
        height: sliderRoot.handleSize
        anchors.verticalCenter: sliderRoot.verticalCenter
        radius: sliderRoot.handleRadius
        color: handleLabel.activeFocus ? sliderRoot.handleActiveColor : sliderRoot.handleColor
        visible: sliderRoot.pathsVisible

        function onHandleDragged()
        {
            sliderRoot.manuallyChanged = true

            // update the range handle
            sliderRoot.updateRangeHandle()

            // set the new value after moving the handle position
            UM.SimulationView.setCurrentPath(getValue())
        }

        // get the value based on the slider position
        function getValue()
        {
            var result = x / (sliderRoot.width - sliderRoot.handleSize)
            result = result * sliderRoot.maximumValue
            result = sliderRoot.roundValues ? Math.round(result) : result
            return result
        }

        function setValueManually(value)
        {
            sliderRoot.manuallyChanged = true
            handle.setValue(value)
        }

        // set the slider position based on the value
        function setValue(value)
        {
            // Normalize values between range, since using arrow keys will create out-of-the-range values
            value = sliderRoot.normalizeValue(value)

            UM.SimulationView.setCurrentPath(value)

            var diff = value / sliderRoot.maximumValue
            var newXPosition = Math.round(diff * (sliderRoot.width - sliderRoot.handleSize))
            x = newXPosition

            // update the range handle
            sliderRoot.updateRangeHandle()
            handleValue = value
        }

        function setHandleLabel(value)
        {
            handleLabel.value = value
            handleLabel.visible = value.length > 0
            handleLabelMetrics.text = value
            handleLabel.width = handleLabelMetrics.width + UM.Theme.getSize("default_margin").width
        }

        Keys.onRightPressed: handle.setValueManually(handleValue + ((event.modifiers & Qt.ShiftModifier) ? 10 : 1))
        Keys.onLeftPressed: handle.setValueManually(handleValue - ((event.modifiers & Qt.ShiftModifier) ? 10 : 1))

        TextMetrics {
            id:     handleLabelMetrics
            font:   valueLabel.font
            text:   ""
        }

        // dragging
        MouseArea
        {
            anchors.fill: parent

            drag
            {
                target: parent
                axis: Drag.XAxis
                minimumX: 0
                maximumX: sliderRoot.width - sliderRoot.handleSize
            }
            onPressed: handleLabel.forceActiveFocus()
            onPositionChanged: parent.onHandleDragged()
        }

        UM.PointingRectangle {
            id: handleLabel

            property string value: ""

            height: sliderRoot.handleSize + UM.Theme.getSize("default_margin").height
            y: parent.y + sliderRoot.handleSize + UM.Theme.getSize("default_margin").height
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom:parent.top
            anchors.bottomMargin: UM.Theme.getSize("narrow_margin").height
            target: Qt.point(x + width / 2, parent.top)

            arrowSize: UM.Theme.getSize("button_tooltip_arrow").height
            width: valueLabel.width
            visible: false

            color: UM.Theme.getColor("tool_panel_background")
            borderColor: UM.Theme.getColor("lining")
            borderWidth: UM.Theme.getSize("default_lining").width

            Behavior on height {
                NumberAnimation {
                    duration: 50
                }
            }

            // catch all mouse events so they're not handled by underlying 3D scene
            MouseArea {
                anchors.fill: parent
            }

            TextField {
                id: valueLabel

                anchors {
                    verticalCenter: parent.verticalCenter
                    horizontalCenter: parent.horizontalCenter
                    alignWhenCentered: false
                }

                width: handleLabelMetrics.width + UM.Theme.getSize("default_margin").width
                text: handleLabel.value
                horizontalAlignment: TextInput.AlignHCenter

                style: TextFieldStyle {
                    textColor: UM.Theme.getColor("text")
                    font: UM.Theme.getFont("default")
                    renderType: Text.NativeRendering
                    background: Item {  }
                }

            }
        }
    }
}
