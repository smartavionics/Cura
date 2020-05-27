[shaders]
vertex =
    #version 320 es
    uniform mediump mat4 u_modelMatrix;

    uniform lowp float u_active_extruder;
    uniform lowp float u_max_feedrate;
    uniform lowp float u_min_feedrate;
    uniform lowp float u_max_thickness;
    uniform lowp float u_min_thickness;
    uniform lowp int u_layer_view_type;
    uniform lowp vec4 u_extruder_opacity;  // currently only for max 4 extruders, others always visible

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
    in highp float a_line_type;
    in highp float a_feedrate;
    in highp float a_thickness;

    out lowp vec4 v_color;
    out lowp vec3 v_vertex;
    //out highp vec2 v_line_dim;
    out mediump float v_line_width;
    out mediump float v_line_height;

    out lowp vec4 f_color;
    out lowp vec3 f_normal;
    out lowp vec3 f_vertex;

    vec4 feedrateGradientColor(float abs_value, float min_value, float max_value)
    {
        float value = (abs_value - min_value)/(max_value - min_value);
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
        float value = (abs_value - min_value)/(max_value - min_value);
        float red = min(max(4.0*value-2.0, 0.0), 1.0);
        float green = min(1.5*value, 0.75);
        if (value > 0.75)
        {
            green = value;
        }
        float blue = 0.75-abs(0.25-value);
        return vec4(red, green, blue, 1.0);
    }

    void main()
    {
        vec4 v1_vertex = a_vertex;
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
        }

        v_vertex = world_space_vert.xyz;
        //v_normal = (u_normalMatrix * normalize(a_normal)).xyz;

        if ((u_extruder_opacity[int(a_extruder)] == 0.0) ||
            ((u_show_travel_moves == 0) && ((a_line_type == 8.0) || (a_line_type == 9.0))) ||
            ((u_show_helpers == 0) && ((a_line_type == 4.0) || (a_line_type == 5.0) || (a_line_type == 7.0) || (a_line_type == 10.0) || a_line_type == 11.0)) ||
            ((u_show_skin == 0) && ((a_line_type == 1.0) || (a_line_type == 2.0) || (a_line_type == 3.0))) ||
            ((u_show_infill == 0) && (a_line_type == 6.0))) {
            v_line_width = 0.0;
            v_line_height = 0.0;
        }
        else if ((a_line_type == 8.0) || (a_line_type == 9.0)) {
            v_line_width = 0.075;
            v_line_height = 0.075;
        }
        else {
            v_line_width = a_line_dim.x * 0.5;
            v_line_height = a_line_dim.y * 0.5;
        }

        // for testing without geometry shader
        f_color = v_color;
        f_vertex = v_vertex;
        //f_normal = v_normal;
    }

geometry =
    #version 320 es

    #define HAVE_VERTEX 0

    uniform mediump mat4 u_viewMatrix;
    uniform mediump mat4 u_projectionMatrix;

    layout(lines) in;
    layout(triangle_strip, max_vertices = 10) out;

    in lowp vec4 v_color[];
    #if HAVE_VERTEX
    in lowp vec3 v_vertex[];
    #endif
    in mediump float v_line_width[];
    in mediump float v_line_height[];

    out lowp vec4 f_color;
    out vec3 f_normal;
    #if HAVE_VERTEX
    out vec3 f_vertex;
    #endif

    mediump mat4 viewProjectionMatrix;

    void emitVertexH(const int index, const float sign, const float offset)
    {
        if (offset > 0.0) {
            #if HAVE_VERTEX
            f_vertex = v_vertex[index];
            #endif
            f_color = v_color[index];
            vec4 vertex_delta = gl_in[1].gl_Position - gl_in[0].gl_Position;
            vec3 normal = sign * normalize(vec3(vertex_delta.z, vertex_delta.y, -vertex_delta.x));
            f_normal = normal;
            gl_Position = viewProjectionMatrix * (gl_in[index].gl_Position + vec4(normal * offset, 0.0));
            EmitVertex();
        }
    }

    void emitVertexV(const int index, const float sign, const float offset)
    {
        if (offset > 0.0) {
            #if HAVE_VERTEX
            f_vertex = v_vertex[index];
            #endif
            f_color = v_color[index];
            f_normal = vec3(0.0, sign, 0.0);
            gl_Position = viewProjectionMatrix * (gl_in[index].gl_Position + vec4(0.0, sign * offset, 0.0, 0.0));
            EmitVertex();
        }
    }

    void main()
    {
        viewProjectionMatrix = u_projectionMatrix * u_viewMatrix;

        if (v_line_width[1] >= 0.05) {

            emitVertexH(0, -1.0, v_line_width[1]);
            emitVertexH(1, -1.0, v_line_width[1]);
            emitVertexV(0, 1.0, v_line_height[1]);
            emitVertexV(1, 1.0, v_line_height[1]);
            emitVertexH(0, 1.0, v_line_width[1]);
            emitVertexH(1, 1.0, v_line_width[1]);
            emitVertexV(0, -1.0, v_line_height[1]);
            emitVertexV(1, -1.0, v_line_height[1]);
            emitVertexH(0, -1.0, v_line_width[1]);
            emitVertexH(1, -1.0, v_line_width[1]);

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
    //in lowp vec3 f_vertex;

    out vec4 frag_color;

    uniform mediump vec4 u_ambientColor;
    uniform mediump vec4 u_minimumAlbedo;
    uniform mediump vec3 u_lightPosition;

    void main()
    {
        vec4 colour = f_color * 0.8 + dot(f_normal, normalize(u_lightPosition)) * 0.2;
        colour.a = f_color.a;
        frag_color = colour;
    }


[defaults]
u_active_extruder = 0.0
u_layer_view_type = 0
u_extruder_opacity = [1.0, 1.0, 1.0, 1.0]

u_specularColor = [0.4, 0.4, 0.4, 1.0]
u_ambientColor = [0.3, 0.3, 0.3, 0.0]
u_diffuseColor = [1.0, 0.79, 0.14, 1.0]
u_minimumAlbedo = [0.1, 0.1, 0.1, 1.0]
u_shininess = 20.0

u_show_travel_moves = 0
u_show_helpers = 1
u_show_skin = 1
u_show_infill = 1

u_min_feedrate = 0
u_max_feedrate = 1

u_min_thickness = 0
u_max_thickness = 1

[bindings]
u_modelMatrix = model_matrix
u_viewMatrix = view_matrix
u_projectionMatrix = projection_matrix
u_normalMatrix = normal_matrix
u_lightPosition = light_0_position

[attributes]
a_vertex = vertex
a_color = color
a_normal = normal
a_line_dim = line_dim
a_extruder = extruder
a_material_color = material_color
a_line_type = line_type
a_feedrate = feedrate
a_thickness = thickness
