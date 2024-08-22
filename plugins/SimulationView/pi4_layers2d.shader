[shaders]
vertex =
    #version 320 es
    uniform mediump mat4 u_modelMatrix;

    uniform lowp float u_active_extruder;
    uniform lowp float u_max_feedrate;
    uniform lowp float u_min_feedrate;
    uniform lowp float u_max_thickness;
    uniform lowp float u_min_thickness;
    uniform lowp float u_max_line_width;
    uniform lowp float u_min_line_width;
    uniform lowp float u_max_flow_rate;
    uniform lowp float u_min_flow_rate;
    uniform lowp int u_layer_view_type;
    uniform lowp mat4 u_extruder_opacity;  // currently only for max 16 extruders, others always visible

    //uniform highp mat4 u_normalMatrix;

    uniform int u_show_travel_moves;
    uniform int u_show_helpers;
    uniform int u_show_skin;
    uniform int u_show_infill;

    in highp vec4 a_vertex;
    in lowp vec4 a_color;
    in lowp vec4 a_material_color;
    in highp vec4 a_normal;
    in highp vec2 a_line_dim;  // line width and thickness
    in highp float a_extruder;
    in highp float a_prev_line_type;
    in highp float a_line_type;
    in highp float a_feedrate;
    in highp float a_thickness;

    out lowp vec4 v_color;
    out vec3 v_vertex;
    //out highp vec2 v_line_dim;
    out mediump float v_line_width;
    out mediump float v_line_height;
    out mediump float v_prev_line_type;
    out mediump float v_line_type;

    out lowp vec4 f_color;
    out vec3 f_normal;

    vec4 feedrateGradientColor(float abs_value, float min_value, float max_value)
    {
        float value;
        if(abs(max_value - min_value) < 0.0001) //Max and min are equal (barring floating point rounding errors).
        {
            value = 0.5; //Pick a colour in exactly the middle of the range.
        }
        else
        {
            value = (abs_value - min_value) / (max_value - min_value);
        }
        float red = value;
        float green = 1.0-abs(1.0-4.0*value);
        if (value > 0.375)
        {
            green = 0.5;
        }
        float blue = max(1.0-4.0*value, 0.0);
        return vec4(red, green, blue, 1.0);
    }

    vec4 layerThicknessGradientColor(float abs_value, float min_value, float max_value)
    {
        float value;
        if(abs(max_value - min_value) < 0.0001) //Max and min are equal (barring floating point rounding errors).
        {
            value = 0.5; //Pick a colour in exactly the middle of the range.
        }
        else
        {
            value = (abs_value - min_value) / (max_value - min_value);
        }
        float red = min(max(4.0*value-2.0, 0.0), 1.0);
        float green = min(1.5*value, 0.75);
        if (value > 0.75)
        {
            green = value;
        }
        float blue = 0.75-abs(0.25-value);
        return vec4(red, green, blue, 1.0);
    }

    vec4 lineWidthGradientColor(float abs_value, float min_value, float max_value)
    {
        float value;
        if(abs(max_value - min_value) < 0.0001) //Max and min are equal (barring floating point rounding errors).
        {
            value = 0.5; //Pick a colour in exactly the middle of the range.
        }
        else
        {
            value = (abs_value - min_value) / (max_value - min_value);
        }
        float red = value;
        float green = 1.0 - abs(1.0 - 4.0 * value);
        if(value > 0.375)
        {
            green = 0.5;
        }
        float blue = max(1.0 - 4.0 * value, 0.0);
        return vec4(red, green, blue, 1.0);
    }

    float clamp1(float v)
    {
        float t = v < 0.0 ? 0.0 : v;
        return t > 1.0 ? 1.0 : t;
    }

    // Inspired by https://stackoverflow.com/a/46628410
    vec4 flowRateGradientColor(float abs_value, float min_value, float max_value)
    {
        float t;
        if(abs(min_value - max_value) < 0.0001)
        {
          t = 0.0;
        }
        else
        {
          t = 2.0 * ((abs_value - min_value) / (max_value - min_value)) - 1.0;
        }
        float red = clamp1(1.5 - abs(2.0 * t - 1.0));
        float green = clamp1(1.5 - abs(2.0 * t));
        float blue = clamp1(1.5 - abs(2.0 * t + 1.0));
        return vec4(red, green, blue, 1.0);
    }

    void main()
    {
        vec4 v1_vertex = a_vertex;
        if ((a_line_type == 8.0) || (a_line_type == 9.0))
            v1_vertex.y += 0.05; // move line slightly above layer
        else
            v1_vertex.y -= a_line_dim.y * 0.5;  // half layer down

        vec4 world_space_vert = u_modelMatrix * v1_vertex;
        gl_Position = world_space_vert;
        // shade the color depending on the extruder index stored in the alpha component of the color

        switch (u_layer_view_type) {
            case 0:  // "Material color"
                v_color = a_material_color;
                break;
            case 1:  // "Line type"
                v_color = vec4(vec3(a_color) * 2.0, a_color.a); // hack alert - compensate for 1/2 brightness used by ProcessSlicedLayersJob
                break;
            case 2:  // "Speed", or technically 'Feedrate'
                v_color = feedrateGradientColor(a_feedrate, u_min_feedrate, u_max_feedrate);
                break;
            case 3:  // "Layer thickness"
                v_color = layerThicknessGradientColor(a_line_dim.y, u_min_thickness, u_max_thickness);
                break;
            case 4:  // "Line width"
                v_color = lineWidthGradientColor(a_line_dim.x, u_min_line_width, u_max_line_width);
                break;
            case 5:  // "Flow"
                float flow_rate =  a_line_dim.x * a_line_dim.y * a_feedrate;
                v_color = flowRateGradientColor(flow_rate, u_min_flow_rate, u_max_flow_rate);
                break;
        }

        v_vertex = world_space_vert.xyz;
        //v_normal = (u_normalMatrix * normalize(a_normal)).xyz;

        if ((u_extruder_opacity[int(mod(a_extruder, 4.0))][int(a_extruder / 4.0)] == 0.0) ||
            ((u_show_travel_moves == 0) && ((a_line_type == 8.0) || (a_line_type == 9.0))) ||
            ((u_show_helpers == 0) && ((a_line_type == 4.0) || (a_line_type == 5.0) || (a_line_type == 7.0) || (a_line_type == 10.0) || a_line_type == 11.0)) ||
            ((u_show_skin == 0) && ((a_line_type == 1.0) || (a_line_type == 2.0) || (a_line_type == 3.0))) ||
            ((u_show_infill == 0) && (a_line_type == 6.0))) {
            v_color.a = 0.0;
        }

        if ((a_line_type == 8.0) || (a_line_type == 9.0)) {
            v_line_width = 0.05;
            v_line_height = 0.05;
        }
        else {
            v_line_width = a_line_dim.x * 0.5;
            v_line_height = a_line_dim.y * 0.5;
        }

        v_prev_line_type = a_prev_line_type;
        v_line_type = a_line_type;

        // for testing without geometry shader
        f_color = v_color;
        //f_normal = v_normal;
    }

geometry =
    #version 320 es

    uniform lowp int u_resolution;

    uniform mediump mat4 u_viewMatrix;
    uniform mediump mat4 u_projectionMatrix;

    uniform mediump vec3 u_viewPosition;
    uniform mediump vec3 u_lightPosition;

    uniform lowp vec4 u_starts_color;
    uniform int u_show_starts;

    layout(lines) in;
    layout(triangle_strip, max_vertices = 11) out;

    in lowp vec4 v_color[];
    in vec3 v_vertex[];
    in mediump float v_line_width[];
    in mediump float v_line_height[];
    in mediump float v_prev_line_type[];
    in mediump float v_line_type[];

    out lowp vec4 f_color;
    out vec3 f_normal;

    mediump mat4 viewProjectionMatrix;

    void outputStartVertex(const vec3 normal, const vec4 offset)
    {
        f_color = u_starts_color;
        f_normal = normal;
        gl_Position = viewProjectionMatrix * (gl_in[0].gl_Position + offset);
        EmitVertex();
    }

    void outputVertex(const int index, const vec3 normal, const float x_offset, const float y_offset)
    {
        f_color = v_color[1];
        f_normal = normal;
        vec4 vertex_delta = gl_in[1].gl_Position - gl_in[0].gl_Position;
        vec4 offset_vec = normalize(vec4(vertex_delta.z, 0.0, -vertex_delta.x, 0.0)) * x_offset;
        offset_vec.y = y_offset;
        gl_Position = viewProjectionMatrix * (gl_in[index].gl_Position + offset_vec);
        EmitVertex();
    }

    void main()
    {
        if (v_color[1].a == 0.0) {
            return;
        }

        viewProjectionMatrix = u_projectionMatrix * u_viewMatrix;

        vec3 view_delta = normalize(u_viewPosition - (v_vertex[0] + v_vertex[1]) * 0.5); // camera to middle of line

        float x_sign = -1.0;

        // fiddle with sign of horizontal offset so that primitive is always tilting towards viewer
        if (((v_vertex[1].x - v_vertex[0].x)*(u_viewPosition.z - v_vertex[0].z) - (v_vertex[1].z - v_vertex[0].z)*(u_viewPosition.x - v_vertex[0].x)) > 0.0) {
            x_sign *= -1.0;
        }
        if (view_delta.y < 0.0) {
            x_sign *= -1.0;
        }

        float x_offset = v_line_width[1];
        float y_offset = v_line_height[1];

        view_delta = -view_delta;

        if (u_resolution == 0 && abs(view_delta.y) > 0.3) {
            // when looking from above or below, shrink the element as this makes the layers more visible
            x_offset *= 0.6;
            y_offset *= 0.6;
        }

        outputVertex(0, -view_delta, -x_sign * x_offset, -y_offset);
        outputVertex(1, -view_delta, -x_sign * x_offset, -y_offset);
        if (u_resolution > 0) {
            outputVertex(0, view_delta, 0.0, 0.0);
            outputVertex(1, view_delta, 0.0, 0.0);
            view_delta = -view_delta;
        }
        outputVertex(0, view_delta, x_sign * x_offset, y_offset);
        outputVertex(1, view_delta, x_sign * x_offset, y_offset);

        EndPrimitive();

        if ((u_show_starts == 1) && (v_prev_line_type[0] != 1.0) && (v_line_type[0] == 1.0)) {
            float w = v_line_width[1] * 1.1;
            float h = v_line_height[1];

            outputStartVertex(normalize(vec3( 1.0,  1.0,  1.0)), vec4( w,  h,  w, 0.0)); // Front-top-left
            outputStartVertex(normalize(vec3( 1.0,  1.0, -1.0)), vec4( w,  h, -w, 0.0)); // Back-top-left
            outputStartVertex(normalize(vec3(-1.0,  1.0,  1.0)), vec4(-w,  h,  w, 0.0)); // Front-top-right
            outputStartVertex(normalize(vec3(-1.0,  1.0, -1.0)), vec4(-w,  h, -w, 0.0)); // Back-top-right
            outputStartVertex(normalize(vec3( 1.0,  1.0, -1.0)), vec4( w,  h, -w, 0.0)); // Back-top-left

            EndPrimitive();
        }
    }

fragment =
    #version 320 es
    #ifdef GL_ES
        #ifdef GL_FRAGMENT_PRECISION_HIGH
            precision highp float;
        #else
            precision mediump float;
        #endif // GL_FRAGMENT_PRECISION_HIGH
    #endif // GL_ES
    in lowp vec4 f_color;
    in vec3 f_normal;

    out vec4 frag_color;

    uniform mediump vec4 u_ambientColor;
    uniform mediump vec4 u_minimumAlbedo;
    uniform mediump vec3 u_lightPosition;

    void main()
    {
        vec4 colour = u_minimumAlbedo + (f_color * (dot(f_normal, normalize(u_lightPosition)) * 0.4 + 0.8));
        colour.a = f_color.a;
        frag_color = colour;
    }


[defaults]
u_active_extruder = 0.0
u_layer_view_type = 0
u_extruder_opacity = [[1.0, 1.0, 1.0, 1.0], [1.0, 1.0, 1.0, 1.0], [1.0, 1.0, 1.0, 1.0], [1.0, 1.0, 1.0, 1.0]]

u_specularColor = [0.4, 0.4, 0.4, 1.0]
u_ambientColor = [0.3, 0.3, 0.3, 0.0]
u_diffuseColor = [1.0, 0.79, 0.14, 1.0]
u_minimumAlbedo = [0.1, 0.1, 0.1, 1.0]
u_shininess = 20.0

u_starts_color = [1.0, 1.0, 1.0, 1.0]

u_show_travel_moves = 0
u_show_helpers = 1
u_show_skin = 1
u_show_infill = 1
u_show_starts = 1

u_min_feedrate = 0
u_max_feedrate = 1

u_min_thickness = 0
u_max_thickness = 1

u_resolution = 1

[bindings]
u_modelMatrix = model_matrix
u_viewMatrix = view_matrix
u_projectionMatrix = projection_matrix
u_normalMatrix = normal_matrix
u_lightPosition = light_0_position
u_viewPosition = view_position

[attributes]
a_vertex = vertex
a_color = color
a_normal = normal
a_line_dim = line_dim
a_extruder = extruder
a_material_color = material_color
a_line_type = line_type
a_prev_line_type = prev_line_type
a_feedrate = feedrate
a_thickness = thickness
