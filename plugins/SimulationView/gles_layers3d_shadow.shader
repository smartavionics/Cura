[shaders]
vertex =
    #version 320 es
    uniform mediump mat4 u_modelMatrix;

    uniform lowp float u_active_extruder;

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

    out lowp vec4 v_color;
    out lowp vec3 v_vertex;
    out lowp float v_line_width;
    out lowp float v_line_height;

    //out highp mat4 v_view_projection_matrix;

    out lowp vec4 f_color;
    out lowp vec3 f_normal;
    out lowp vec3 f_vertex;

    void main()
    {
        vec4 v1_vertex = a_vertex;
        v1_vertex.y -= a_line_dim.y * 0.5;  // half layer down

        vec4 world_space_vert = u_modelMatrix * v1_vertex;
        gl_Position = world_space_vert;
        // shade the color depending on the extruder index stored in the alpha component of the color

        v_color = vec4(0.4, 0.4, 0.4, 0.9);    // default color for not current layer

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
    uniform mediump mat4 u_viewMatrix;
    uniform mediump mat4 u_projectionMatrix;
    uniform mediump vec3 u_lightPosition;

    layout(lines) in;
    layout(triangle_strip, max_vertices = 10) out;

    in lowp vec4 v_color[];
    in lowp vec3 v_vertex[];
    in lowp float v_line_width[];
    in lowp float v_line_height[];

    out vec4 f_color;
    out vec3 f_normal;
    out vec3 f_vertex;

    mediump mat4 viewProjectionMatrix;

    void myEmitVertex0(const mediump vec3 normal, const mediump vec4 pos_offset)
    {
        f_vertex = v_vertex[0];
        f_color = v_color[0];
        f_normal = normal;
        gl_Position = viewProjectionMatrix * (gl_in[0].gl_Position + pos_offset);
        EmitVertex();
    }

    void myEmitVertex1(const mediump vec3 normal, const mediump vec4 pos_offset)
    {
        f_vertex = v_vertex[1];
        f_color = v_color[1];
        f_normal = normal;
        gl_Position = viewProjectionMatrix * (gl_in[1].gl_Position + pos_offset);
        EmitVertex();
    }

    void main()
    {
        if (v_line_width[1] != 0.0) {

            #define HAVE_FLIP 1
            #define HAVE_VERT 0

            viewProjectionMatrix = u_projectionMatrix * u_viewMatrix;

            #if HAVE_FLIP
            mediump vec3 vertex_normal;
            mediump vec4 vertex_offset;
            if (abs(normalize(u_lightPosition - (v_vertex[0] + v_vertex[1]) * 0.5).y) > 0.5) {
                mediump vec4 vertex_delta = gl_in[1].gl_Position - gl_in[0].gl_Position;
                vertex_normal = normalize(vec3(vertex_delta.z, vertex_delta.y, -vertex_delta.x));
                vertex_offset = vec4(vertex_normal * v_line_width[1], 0.0);
            }
            else {
                vertex_normal = vec3(0.0, 1.0, 0.0);
                vertex_offset = vec4(vertex_normal * v_line_height[1], 0.0);
            }

            myEmitVertex0(-vertex_normal, -vertex_offset);
            myEmitVertex1(-vertex_normal, -vertex_offset);
            myEmitVertex0(vertex_normal, vertex_offset);
            myEmitVertex1(vertex_normal, vertex_offset);
            myEmitVertex0(-vertex_normal, -vertex_offset);
            myEmitVertex1(-vertex_normal, -vertex_offset);

            #else // !HAVE_FLIP

            precise mediump vec4 g_vertex_delta = gl_in[1].gl_Position - gl_in[0].gl_Position;
            precise mediump vec3 g_vertex_normal_horz = normalize(vec3(g_vertex_delta.z, g_vertex_delta.y, -g_vertex_delta.x));

            #if HAVE_VERT
            precise lowp vec3 g_vertex_normal_vert = vec3(0.0, 1.0, 0.0);
            precise mediump vec4 g_vertex_offset_vert = vec4(g_vertex_normal_vert * v_line_height[1], 0.0);
            #endif

            {
                precise mediump vec4 g_vertex_offset_horz = vec4(g_vertex_normal_horz * v_line_width[1], 0.0);

                myEmitVertex0(-g_vertex_normal_horz, -g_vertex_offset_horz);
                myEmitVertex1(-g_vertex_normal_horz, -g_vertex_offset_horz);
            }

            #if HAVE_VERT
            {
                precise mediump vec4 g_vertex_offset_vert = vec4(g_vertex_normal_vert * v_line_height[1], 0.0);

                myEmitVertex0(g_vertex_normal_vert, g_vertex_offset_vert);
                myEmitVertex1(g_vertex_normal_vert, g_vertex_offset_vert);
            }
            #endif

            {
                precise mediump vec4 g_vertex_offset_horz = vec4(g_vertex_normal_horz * v_line_width[1], 0.0);

                myEmitVertex0(g_vertex_normal_horz, g_vertex_offset_horz);
                myEmitVertex1(g_vertex_normal_horz, g_vertex_offset_horz);
            }

            #if HAVE_VERT
            {
                precise mediump vec4 g_vertex_offset_vert = vec4(g_vertex_normal_vert * v_line_height[1], 0.0);

                myEmitVertex0(-g_vertex_normal_vert, -g_vertex_offset_vert);
                myEmitVertex1(-g_vertex_normal_vert, -g_vertex_offset_vert);
            }
            #endif

            {
                precise mediump vec4 g_vertex_offset_horz = vec4(g_vertex_normal_horz * v_line_width[1], 0.0);

                myEmitVertex0(-g_vertex_normal_horz, -g_vertex_offset_horz);
                myEmitVertex1(-g_vertex_normal_horz, -g_vertex_offset_horz);
            }
            #endif // !HAVE_FLIP
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
    in lowp vec3 f_normal;
    in lowp vec3 f_vertex;

    out vec4 frag_color;

    uniform mediump vec4 u_ambientColor;
    uniform mediump vec3 u_lightPosition;

    void main()
    {
        mediump vec4 finalColor = vec4(0.0);
        float alpha = f_color.a;

        finalColor.rgb += f_color.rgb * 0.8;

        highp vec3 normal = normalize(f_normal);
        highp vec3 light_dir = normalize(u_lightPosition - f_vertex);

        // Diffuse Component
        highp float NdotL = clamp(dot(normal, light_dir), 0.0, 0.2);
        finalColor += (NdotL * f_color);
        finalColor.a = alpha;  // Do not change alpha in any way

        frag_color = finalColor;
    }


[defaults]
u_active_extruder = 0.0
u_layer_view_type = 0
u_extruder_opacity = [1.0, 1.0, 1.0, 1.0]

u_specularColor = [0.4, 0.4, 0.4, 1.0]
u_ambientColor = [0.3, 0.3, 0.3, 0.0]
u_diffuseColor = [1.0, 0.79, 0.14, 1.0]
u_shininess = 20.0

u_show_travel_moves = 0
u_show_helpers = 1
u_show_skin = 1
u_show_infill = 1

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

