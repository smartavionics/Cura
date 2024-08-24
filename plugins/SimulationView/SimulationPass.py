# Copyright (c) 2020 Ultimaker B.V.
# Cura is released under the terms of the LGPLv3 or higher.

from UM.Math.Color import Color
from UM.Math.Vector import Vector
from UM.Scene.Iterator.DepthFirstIterator import DepthFirstIterator
from UM.Resources import Resources
from UM.Scene.SceneNode import SceneNode
from UM.Scene.ToolHandle import ToolHandle
from UM.Application import Application
from UM.PluginRegistry import PluginRegistry

from UM.View.RenderPass import RenderPass
from UM.View.RenderBatch import RenderBatch
from UM.View.GL.OpenGL import OpenGL

from cura.Settings.ExtruderManager import ExtruderManager

from PyQt5 import QtCore, QtWidgets

from copy import deepcopy

import os.path
import os
import numpy

from cura.LayerPolygon import LayerPolygon

## RenderPass used to display g-code paths.
from .NozzleNode import NozzleNode


class SimulationPass(RenderPass):
    def __init__(self, width, height, enable_aa):
        super().__init__("simulationview", width, height, 0, enable_aa)

        self._layer_shader = None
        self._layer_shader_2d = None
        self._layer_shadow_shader = None
        self._current_shader = None # This shader will be the shadow or the normal depending if the user wants to see the paths or the layers
        self._tool_handle_shader = None
        self._nozzle_shader = None
        self._disabled_shader = None
        self._old_current_layer = 0
        self._old_current_path = 0
        self._switching_layers = True  # Tracking whether the user is moving across layers (True) or across paths (False). If false, lower layers render as shadowy.
        self._gl = OpenGL.getInstance().getBindingsObject()
        self._scene = Application.getInstance().getController().getScene()
        self._extruder_manager = ExtruderManager.getInstance()

        self._layer_view = None
        self._compatibility_mode = None

        self._max_3d_elements = None
        if "CURA_MAX_LAYER_VIEW_3D_ELEMENTS" in os.environ:
            try:
                self._max_3d_elements = int(os.environ["CURA_MAX_LAYER_VIEW_3D_ELEMENTS"])
            except:
                pass

        self._resolution = None
        if "CURA_LAYER_VIEW_RESOLUTION" in os.environ:
            try:
                self._resolution = int(os.environ["CURA_LAYER_VIEW_RESOLUTION"])
            except:
                pass

        self._scene.sceneChanged.connect(self._onSceneChanged)

    def setSimulationView(self, layerview):
        self._layer_view = layerview
        self._compatibility_mode = layerview.getCompatibilityMode()
        self._pi4_shaders = layerview._have_gles_geometry_shader
        if self._max_3d_elements is None:
            self._max_3d_elements = 500000 * (3 if self._layer_view._on_pi5 else 1)
        if self._resolution is None and self._layer_view._on_pi5:
            self._resolution = 1

    def render(self):
        if not self._layer_shader:
            if self._compatibility_mode:
                shader_filename = "layers.shader"
                shadow_shader_filename = "layers_shadow.shader"
            elif self._pi4_shaders:
                # use simplified shaders that perform better on the PI 4
                if self._layer_view._use_pi5_layer_shader:
                    shader_filename = "pi5_layers3d.shader"
                else:
                    shader_filename = "pi4_layers3d.shader"
                shadow_shader_filename = "pi4_layers2d_shadow.shader"
                self._layer_shader_2d = OpenGL.getInstance().createShaderProgram(os.path.join(PluginRegistry.getInstance().getPluginPath("SimulationView"), "pi4_layers2d.shader"))
            else:
                shader_filename = "layers3d.shader"
                shadow_shader_filename = "layers3d_shadow.shader"
            self._layer_shader = OpenGL.getInstance().createShaderProgram(os.path.join(PluginRegistry.getInstance().getPluginPath("SimulationView"), shader_filename))
            self._layer_shadow_shader = OpenGL.getInstance().createShaderProgram(os.path.join(PluginRegistry.getInstance().getPluginPath("SimulationView"), shadow_shader_filename))
            self._current_shader = self._layer_shader
        # Use extruder 0 if the extruder manager reports extruder index -1 (for single extrusion printers)
        self._layer_shader.setUniformValue("u_active_extruder", float(max(0, self._extruder_manager.activeExtruderIndex)))
        if not self._compatibility_mode:
            self._layer_shader.setUniformValue("u_starts_color", Color(*Application.getInstance().getTheme().getColor("layerview_starts").getRgb()))

        if not self._pi4_shaders and self._layer_view:
            # slightly increase u_max_feedrate to avoid DBZ in shader when max and min feedrates are equal
            self._layer_shader.setUniformValue("u_max_feedrate", self._layer_view.getMaxFeedrate() + 0.01)
            self._layer_shader.setUniformValue("u_min_feedrate", self._layer_view.getMinFeedrate())
            self._layer_shader.setUniformValue("u_max_thickness", self._layer_view.getMaxThickness())
            self._layer_shader.setUniformValue("u_min_thickness", self._layer_view.getMinThickness())
            self._layer_shader.setUniformValue("u_max_line_width", self._layer_view.getMaxLineWidth())
            self._layer_shader.setUniformValue("u_min_line_width", self._layer_view.getMinLineWidth())
            self._layer_shader.setUniformValue("u_max_flow_rate", self._layer_view.getMaxFlowRate())
            self._layer_shader.setUniformValue("u_min_flow_rate", self._layer_view.getMinFlowRate())
            self._layer_shader.setUniformValue("u_layer_view_type", self._layer_view.getSimulationViewType())
            self._layer_shader.setUniformValue("u_extruder_opacity", self._layer_view.getExtruderOpacities())
            self._layer_shader.setUniformValue("u_show_travel_moves", self._layer_view.getShowTravelMoves())
            self._layer_shader.setUniformValue("u_show_helpers", self._layer_view.getShowHelpers())
            self._layer_shader.setUniformValue("u_show_skin", self._layer_view.getShowSkin())
            self._layer_shader.setUniformValue("u_show_infill", self._layer_view.getShowInfill())
            self._layer_shader.setUniformValue("u_show_starts", self._layer_view.getShowStarts())
        elif not self._pi4_shaders:
            #defaults
            self._layer_shader.setUniformValue("u_max_feedrate", 1)
            self._layer_shader.setUniformValue("u_min_feedrate", 0)
            self._layer_shader.setUniformValue("u_max_thickness", 1)
            self._layer_shader.setUniformValue("u_min_thickness", 0)
            self._layer_shader.setUniformValue("u_max_flow_rate", 1)
            self._layer_shader.setUniformValue("u_min_flow_rate", 0)
            self._layer_shader.setUniformValue("u_max_line_width", 1)
            self._layer_shader.setUniformValue("u_min_line_width", 0)
            self._layer_shader.setUniformValue("u_layer_view_type", 1)
            self._layer_shader.setUniformValue("u_extruder_opacity", [[1, 1, 1, 1], [1, 1, 1, 1], [1, 1, 1, 1], [1, 1, 1, 1]])
            self._layer_shader.setUniformValue("u_show_travel_moves", 0)
            self._layer_shader.setUniformValue("u_show_helpers", 1)
            self._layer_shader.setUniformValue("u_show_skin", 1)
            self._layer_shader.setUniformValue("u_show_infill", 1)
            self._layer_shader.setUniformValue("u_show_starts", 1)

        if not self._tool_handle_shader:
            self._tool_handle_shader = OpenGL.getInstance().createShaderProgram(Resources.getPath(Resources.Shaders, "toolhandle.shader"))

        if not self._nozzle_shader:
            self._nozzle_shader = OpenGL.getInstance().createShaderProgram(Resources.getPath(Resources.Shaders, "color.shader"))
            self._nozzle_shader.setUniformValue("u_color", Color(*Application.getInstance().getTheme().getColor("layerview_nozzle").getRgb()))

        if not self._disabled_shader:
            self._disabled_shader = OpenGL.getInstance().createShaderProgram(Resources.getPath(Resources.Shaders, "striped.shader"))
            self._disabled_shader.setUniformValue("u_diffuseColor1", Color(*Application.getInstance().getTheme().getColor("model_unslicable").getRgb()))
            self._disabled_shader.setUniformValue("u_diffuseColor2", Color(*Application.getInstance().getTheme().getColor("model_unslicable_alt").getRgb()))
            self._disabled_shader.setUniformValue("u_width", 50.0)
            self._disabled_shader.setUniformValue("u_opacity", 0.6)

        self.bind()

        tool_handle_batch = RenderBatch(self._tool_handle_shader, type = RenderBatch.RenderType.Overlay, backface_cull = True)
        disabled_batch = RenderBatch(self._disabled_shader)
        head_position = None  # Indicates the current position of the print head
        nozzle_node = None

        ride_the_nozzle = (self._old_current_path != self._layer_view._current_path_num and
                            ((QtWidgets.QApplication.queryKeyboardModifiers() & QtCore.Qt.AltModifier) == QtCore.Qt.AltModifier))
        camera_position = None
        elevation = 1.0 # mm
        trail_by = 5.0 #mm

        if not ride_the_nozzle and self._scene.getActiveCamera().getName() != "3d":
            self._scene.setActiveCamera("3d")

        self._layer_view._current_path_info = ""

        for node in DepthFirstIterator(self._scene.getRoot()):

            if isinstance(node, ToolHandle):
                tool_handle_batch.addItem(node.getWorldTransformation(), mesh = node.getSolidMesh())

            elif isinstance(node, NozzleNode):
                nozzle_node = node
                nozzle_node.setVisible(False)  # Don't set to true, we render it separately!

            elif getattr(node, "_outside_buildarea", False) and isinstance(node, SceneNode) and node.getMeshData() and node.isVisible() and not node.callDecoration("isNonPrintingMesh"):
                disabled_batch.addItem(node.getWorldTransformation(copy=False), node.getMeshData())

            elif isinstance(node, SceneNode) and (node.getMeshData() or node.callDecoration("isBlockSlicing")) and node.isVisible():
                layer_data = node.callDecoration("getLayerData")
                if not layer_data:
                    continue

                # Render all layers below a certain number as line mesh instead of vertices.
                if self._layer_view._current_layer_num > -1 and ((not self._layer_view._only_show_top_layers) or (not self._layer_view.getCompatibilityMode())):
                    start = 0
                    end = 0
                    element_counts = layer_data.getElementCounts()
                    for layer in sorted(element_counts.keys()):
                        # In the current layer, we show just the indicated paths
                        if layer == self._layer_view._current_layer_num:
                            # We look for the position of the head, searching the point of the current path
                            index = self._layer_view._current_path_num
                            offset = 0
                            for polygon in layer_data.getLayer(layer).polygons:
                                # The size indicates all values in the two-dimension array, and the second dimension is
                                # always size 3 because we have 3D points.
                                if index >= polygon.data.size // 3 - offset:
                                    index -= polygon.data.size // 3 - offset
                                    offset = 1  # This is to avoid the first point when there is more than one polygon, since has the same value as the last point in the previous polygon
                                    continue
                                # The head position is calculated and translated
                                head_position = Vector(polygon.data[index+offset][0], polygon.data[index+offset][1], polygon.data[index+offset][2]) + node.getWorldPosition()
                                if self._layer_view._display_line_details and index+offset > 0:
                                    from_location = polygon.data[index+offset-1];
                                    to_location = polygon.data[index+offset];
                                    line_type = polygon.types[index+offset-1][0]
                                    line_feedrate = polygon.lineFeedrates[index+offset-1][0]
                                    line_width = polygon.lineWidths[index+offset-1][0]
                                    line_depth = polygon.lineThicknesses[index+offset-1][0]
                                    prev_position = Vector(from_location[0], from_location[1], from_location[2]) + node.getWorldPosition()
                                    line_length = (head_position - prev_position).length()
                                    types = [ "None", "Outer wall", "Inner wall", "Skin", "Support", "Skirt/Brim", "Infill", "Support infill", "Travel", "Travel (retracted)", "Support interface", "Prime tower"]
                                    line_flow = line_feedrate * line_width * line_depth
                                    # why is python number formatting so crap?
                                    def f(x):
                                        if x == int(x):
                                            return str(int(x))
                                        return "{:.3f}".format(x)
                                    from_coords = "x={0}, y={1}, z={2}".format(f(from_location[0]), f(from_location[2]), f(from_location[1]))
                                    to_coords = "x={0}, y={1}, z={2}".format(f(to_location[0]), f(to_location[2]), f(to_location[1]))
                                    self._layer_view._current_path_info = types[line_type] + ";" + from_coords + ";" + to_coords + ";{0};{1};{2}".format(f(line_length), f(line_feedrate), f(line_flow))
                                    if line_flow != 0:
                                        self._layer_view._current_path_info += ";{0};{1}".format(f(line_width), f(line_depth))
                                if ride_the_nozzle and index+offset > 0:
                                    prev_position = Vector(polygon.data[index+offset-1][0], polygon.data[index+offset-1][1], polygon.data[index+offset-1][2]) + node.getWorldPosition()
                                    camera_position = head_position - (head_position - prev_position).normalized() * trail_by
                                break
                            break
                        if self._layer_view._minimum_layer_num > layer:
                            start += element_counts[layer]
                        end += element_counts[layer]

                    # Calculate the range of paths in the last layer
                    current_layer_start = end
                    current_layer_end = end + self._layer_view._current_path_num * 2 # Because each point is used twice

                    # This uses glDrawRangeElements internally to only draw a certain range of lines.
                    # All the layers but the current selected layer are rendered first
                    if self._old_current_path != self._layer_view._current_path_num:
                        self._current_shader = self._layer_shadow_shader
                        self._switching_layers = False
                    if not self._layer_view.isSimulationRunning() and self._old_current_layer != self._layer_view._current_layer_num:
                        self._current_shader = self._layer_shader
                        self._switching_layers = True

                    if ride_the_nozzle and camera_position is not None:
                        if self._scene.getActiveCamera().getName() != "nozzle_cam":
                            if self._scene.findCamera("nozzle_cam") is None:
                                nozzle_cam = deepcopy(self._scene.getActiveCamera())
                                nozzle_cam.setName("nozzle_cam")
                                nozzle_cam.setPerspective(True)
                                self._scene.getRoot().addChild(nozzle_cam)
                            self._scene.setActiveCamera("nozzle_cam")

                        self._scene.getActiveCamera().setPosition(camera_position + Vector(0.0, elevation, 0.0))
                        self._scene.getActiveCamera().lookAt(head_position + Vector(0.0, elevation, 0.0));

                        if self._layer_view.getSimulationViewType() == 0:
                            # don't use shadow shader when rendering in material colour
                            self._current_shader = self._layer_shader

                    if self._layer_shader_2d and self._current_shader != self._layer_shadow_shader:
                        if (end - start) < self._max_3d_elements:
                            self._current_shader = self._layer_shader
                        else:
                            self._current_shader = self._layer_shader_2d
                            resolution = 1
                            if self._resolution is None:
                                camera = self._scene.getActiveCamera()
                                if camera.isPerspective():
                                    if camera.getWorldPosition().length() > 200.0:
                                        resolution = 0
                                else:
                                    if camera.getZoomFactor() > -0.45:
                                        resolution = 0
                            else:
                                resolution = self._resolution
                            self._current_shader.setUniformValue("u_resolution", resolution)

                    if self._pi4_shaders:
                        self._current_shader.setUniformValue("u_active_extruder", float(max(0, self._extruder_manager.activeExtruderIndex)))
                        # slightly increase u_max_feedrate to avoid DBZ in shader when max and min feedrates are equal
                        self._current_shader.setUniformValue("u_max_feedrate", self._layer_view.getMaxFeedrate() + 0.01)
                        self._current_shader.setUniformValue("u_min_feedrate", self._layer_view.getMinFeedrate())
                        self._current_shader.setUniformValue("u_max_thickness", self._layer_view.getMaxThickness())
                        self._current_shader.setUniformValue("u_min_thickness", self._layer_view.getMinThickness())
                        self._current_shader.setUniformValue("u_max_line_width", self._layer_view.getMaxLineWidth())
                        self._current_shader.setUniformValue("u_min_line_width", self._layer_view.getMinLineWidth())
                        self._current_shader.setUniformValue("u_max_flow_rate", self._layer_view.getMaxFlowRate())
                        self._current_shader.setUniformValue("u_min_flow_rate", self._layer_view.getMinFlowRate())
                        self._current_shader.setUniformValue("u_layer_view_type", self._layer_view.getSimulationViewType())
                        self._current_shader.setUniformValue("u_extruder_opacity", self._layer_view.getExtruderOpacities())
                        if self._current_shader != self._layer_shadow_shader:
                            self._current_shader.setUniformValue("u_show_travel_moves", self._layer_view.getShowTravelMoves())
                        self._current_shader.setUniformValue("u_show_helpers", self._layer_view.getShowHelpers())
                        self._current_shader.setUniformValue("u_show_skin", self._layer_view.getShowSkin())
                        self._current_shader.setUniformValue("u_show_infill", self._layer_view.getShowInfill())
                        self._current_shader.setUniformValue("u_starts_color", Color(*Application.getInstance().getTheme().getColor("layerview_starts").getRgb()))
                        self._current_shader.setUniformValue("u_show_starts", self._layer_view.getShowStarts())
                        if self._current_shader != self._layer_shader:
                            # slightly increase u_max_feedrate to avoid DBZ in shader when max and min feedrates are equal
                            self._layer_shader.setUniformValue("u_max_feedrate", self._layer_view.getMaxFeedrate() + 0.01)
                            self._layer_shader.setUniformValue("u_min_feedrate", self._layer_view.getMinFeedrate())
                            self._layer_shader.setUniformValue("u_max_thickness", self._layer_view.getMaxThickness())
                            self._layer_shader.setUniformValue("u_min_thickness", self._layer_view.getMinThickness())
                            self._layer_shader.setUniformValue("u_max_line_width", self._layer_view.getMaxLineWidth())
                            self._layer_shader.setUniformValue("u_min_line_width", self._layer_view.getMinLineWidth())
                            self._layer_shader.setUniformValue("u_max_flow_rate", self._layer_view.getMaxFlowRate())
                            self._layer_shader.setUniformValue("u_min_flow_rate", self._layer_view.getMinFlowRate())
                            self._layer_shader.setUniformValue("u_layer_view_type", self._layer_view.getSimulationViewType())
                            self._layer_shader.setUniformValue("u_extruder_opacity", self._layer_view.getExtruderOpacities())
                            self._layer_shader.setUniformValue("u_show_travel_moves", self._layer_view.getShowTravelMoves())
                            self._layer_shader.setUniformValue("u_show_helpers", self._layer_view.getShowHelpers())
                            self._layer_shader.setUniformValue("u_show_skin", self._layer_view.getShowSkin())
                            self._layer_shader.setUniformValue("u_show_infill", self._layer_view.getShowInfill())
                            self._layer_shader.setUniformValue("u_show_starts", self._layer_view.getShowStarts())

                    # The first line does not have a previous line: add a MoveCombingType in front for start detection
                    # this way the first start of the layer can also be drawn
                    prev_line_types = numpy.concatenate([numpy.asarray([LayerPolygon.MoveCombingType], dtype = numpy.float32), layer_data._attributes["line_types"]["value"]])
                    # Remove the last element
                    prev_line_types = prev_line_types[0:layer_data._attributes["line_types"]["value"].size]
                    layer_data._attributes["prev_line_types"] =  {'opengl_type': 'float', 'value': prev_line_types, 'opengl_name': 'a_prev_line_type'}

                    # for the PI 4, only bother to output the lower layers using the shadow shader when riding the nozzle
                    if not self._pi4_shaders or self._current_shader != self._layer_shadow_shader or ride_the_nozzle:
                        backface_cull = not self._pi4_shaders or self._current_shader == self._layer_shadow_shader
                        layers_batch = RenderBatch(self._current_shader, type = RenderBatch.RenderType.Solid, mode = RenderBatch.RenderMode.Lines, range = (start, end), backface_cull = backface_cull)
                        layers_batch.addItem(node.getWorldTransformation(), layer_data)
                        layers_batch.render(self._scene.getActiveCamera())

                    # Current selected layer is rendered
                    current_layer_batch = RenderBatch(self._layer_shader, type = RenderBatch.RenderType.Solid, mode = RenderBatch.RenderMode.Lines, range = (current_layer_start, current_layer_end))
                    current_layer_batch.addItem(node.getWorldTransformation(), layer_data)
                    current_layer_batch.render(self._scene.getActiveCamera())

                    self._old_current_layer = self._layer_view._current_layer_num
                    self._old_current_path = self._layer_view._current_path_num

                # Create a new batch that is not range-limited
                batch = RenderBatch(self._layer_shader, type = RenderBatch.RenderType.Solid)

                if self._layer_view.getCurrentLayerMesh():
                    batch.addItem(node.getWorldTransformation(), self._layer_view.getCurrentLayerMesh())

                if self._layer_view.getCurrentLayerJumps():
                    batch.addItem(node.getWorldTransformation(), self._layer_view.getCurrentLayerJumps())

                if len(batch.items) > 0:
                    batch.render(self._scene.getActiveCamera())

        # The nozzle is drawn when once we know the correct position of the head,
        # but the user is not using the layer slider, and the compatibility mode is not enabled
        if not self._switching_layers and not self._compatibility_mode and self._layer_view.getActivity() and nozzle_node is not None:
            if head_position is not None and not ride_the_nozzle:
                nozzle_node.setVisible(True)
                nozzle_node.setPosition(head_position)
                nozzle_batch = RenderBatch(self._nozzle_shader, type = RenderBatch.RenderType.Transparent)
                nozzle_batch.addItem(nozzle_node.getWorldTransformation(), mesh = nozzle_node.getMeshData())
                nozzle_batch.render(self._scene.getActiveCamera())

        self._layer_view.currentPathInfoChanged.emit()

        if len(disabled_batch.items) > 0:
            disabled_batch.render(self._scene.getActiveCamera())

        # Render toolhandles on top of the layerview
        if len(tool_handle_batch.items) > 0:
            tool_handle_batch.render(self._scene.getActiveCamera())

        self.release()

    def _onSceneChanged(self, changed_object: SceneNode):
        if changed_object.callDecoration("getLayerData"):  # Any layer data has changed.
            self._switching_layers = True
            self._old_current_layer = 0
            self._old_current_path = 0
