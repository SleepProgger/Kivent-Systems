# cython: profile=True
# cython: embedsignature=True
from cpython cimport bool
from kivy.properties import (
    BooleanProperty, StringProperty, NumericProperty, ListProperty
    )
from kivy.graphics import Callback
from kivy.graphics.instructions cimport RenderContext
from kivent_core.rendering.vertex_formats cimport (
    VertexFormat4F, VertexFormat2F4UB, VertexFormat7F, VertexFormat4F4UB,
    VertexFormat7F4UB
    )
from kivent_core.rendering.vertex_formats import (
    vertex_format_4f, vertex_format_7f, vertex_format_4f4ub, 
    vertex_format_2f4ub, vertex_format_7f4ub
    )
from kivent_core.rendering.vertex_format cimport KEVertexFormat
from kivent_core.rendering.cmesh cimport CMesh
from kivent_core.rendering.batching cimport BatchManager, IndexedBatch
from kivent_core.managers.resource_managers import texture_manager
from kivent_core.managers.resource_managers cimport ModelManager, TextureManager
from kivy.graphics.opengl import (
    glEnable, glDisable, glBlendFunc, GL_SRC_ALPHA, GL_ONE, 
    GL_ZERO, GL_SRC_COLOR, GL_ONE_MINUS_SRC_COLOR, GL_ONE_MINUS_SRC_ALPHA, 
    GL_DST_ALPHA, GL_ONE_MINUS_DST_ALPHA, GL_DST_COLOR, GL_ONE_MINUS_DST_COLOR,
    )
cimport cython
from kivy.graphics.cgl cimport GLfloat, GLushort
from kivent_core.systems.staticmemgamesystem cimport StaticMemGameSystem, MemComponent
from kivent_core.systems.position_systems cimport PositionStruct2D
from kivent_core.systems.rotate_systems cimport RotateStruct2D
from kivent_core.systems.scale_systems cimport ScaleStruct2D
from kivent_core.systems.color_systems cimport ColorStruct
from kivent_core.entity cimport Entity
from kivent_core.rendering.model cimport VertexModel
from kivy.factory import Factory
from libc.math cimport fabs
from kivent_core.memory_handlers.indexing cimport IndexedMemoryZone
from kivent_core.memory_handlers.zone cimport MemoryZone
from kivent_core.memory_handlers.membuffer cimport Buffer
from kivent_core.systems.staticmemgamesystem cimport ComponentPointerAggregator
from kivent_core.memory_handlers.block cimport MemoryBlock
from kivy.properties import ObjectProperty, NumericProperty
from kivy.clock import Clock
from kivent_core.rendering.gl_debug cimport gl_log_debug_message
from functools import partial

# TODO: check which imports are needed

from kivent_core.systems.renderers cimport RenderStruct



cdef class RotateColorScaleRenderer(RotateColorRenderer):
    '''
    Processing Depends On: PositionSystem2D, RotateSystem2D,
    ColorSystem, ScaleSystem2D, RotateColorScaleRenderer
    The renderer draws with the VertexFormat7F4UB:
    .. code-block:: cython
        ctypedef struct VertexFormat7F:
            GLfloat[2] pos
            GLfloat[2] uvs
            GLfloat rot
            GLfloat[2] center
            GLubyte[4] v_color
    This renderer draws every entity with rotation data suitable
    for use with entities using the CymunkPhysics GameSystems. 
    '''
    
    system_names = ListProperty(['rotate_color_scale_renderer', 'position', 'rotate', 'color', 'scale'])
    system_id = StringProperty('rotate_color_scale_renderer')

    def update(self, force_update, dt):
        cdef IndexedBatch batch
        cdef list batches
        cdef unsigned int batch_key
        cdef unsigned int index_offset, vert_offset
        cdef RenderStruct* render_comp
        cdef PositionStruct2D* pos_comp
        cdef RotateStruct2D* rot_comp
        cdef ScaleStruct2D* scale_comp
        cdef VertexFormat7F4UB* frame_data
        cdef GLushort* frame_indices
        cdef VertexFormat7F4UB* vertex
        cdef ColorStruct* color_comp
        cdef VertexModel model
        cdef GLushort* model_indices
        cdef VertexFormat4F* model_vertices
        cdef VertexFormat4F model_vertex
        cdef unsigned int used, i, ri, component_count, n, t
        cdef ComponentPointerAggregator entity_components
        cdef BatchManager batch_manager = self.batch_manager
        cdef dict batch_groups = batch_manager.batch_groups
        cdef CMesh mesh_instruction
        cdef MemoryBlock components_block
        cdef void** component_data
        cdef bint static_rendering = self.static_rendering

        for batch_key in batch_groups:
            batches = batch_groups[batch_key]
            for batch in batches:
                if not static_rendering or force_update:
                    entity_components = batch.entity_components
                    components_block = entity_components.memory_block
                    used = components_block.used_count
                    component_count = entity_components.count
                    component_data = <void**>components_block.data
                    frame_data = <VertexFormat7F4UB*>batch.get_vbo_frame_to_draw()
                    frame_indices = <GLushort*>batch.get_indices_frame_to_draw()
                    index_offset = 0
                    for t in range(used):
                        ri = t * component_count
                        if component_data[ri] == NULL:
                            continue
                        render_comp = <RenderStruct*>component_data[ri+0]
                        vert_offset = render_comp.vert_index
                        model = <VertexModel>render_comp.model
                        if render_comp.render:
                            pos_comp = <PositionStruct2D*>component_data[ri+1]
                            rot_comp = <RotateStruct2D*>component_data[ri+2]
                            color_comp = <ColorStruct*>component_data[ri+3]
                            scale_comp = <ScaleStruct2D*>component_data[ri+4]
                            model_vertices = <VertexFormat4F*>(
                                model.vertices_block.data)
                            model_indices = <GLushort*>model.indices_block.data
                            for i in range(model._index_count):
                                frame_indices[i+index_offset] = (
                                    model_indices[i] + vert_offset)
                            for n in range(model._vertex_count):
                                vertex = &frame_data[n + vert_offset]
                                model_vertex = model_vertices[n]
                                vertex.pos[0] = model_vertex.pos[0] * scale_comp.sx
                                vertex.pos[1] = model_vertex.pos[1] * scale_comp.sy
                                
                                
                                # TODO: do i have to scale the uvs too ?
                                vertex.uvs[0] = model_vertex.uvs[0]
                                vertex.uvs[1] = model_vertex.uvs[1]
                                vertex.rot = rot_comp.r
                                vertex.center[0] = pos_comp.x
                                vertex.center[1] = pos_comp.y
                                vertex.v_color[0] = color_comp.color[0]
                                vertex.v_color[1] = color_comp.color[1]
                                vertex.v_color[2] = color_comp.color[2]
                                vertex.v_color[3] = color_comp.color[3]

                            index_offset += model._index_count
                    batch.set_index_count_for_frame(index_offset)
                mesh_instruction = batch.mesh_instruction
                mesh_instruction.flag_update()
                
Factory.register('RotateColorScaleRenderer', cls=RotateColorScaleRenderer)