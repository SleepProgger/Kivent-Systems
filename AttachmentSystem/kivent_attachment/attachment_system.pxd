from kivent_core.systems.staticmemgamesystem cimport StaticMemGameSystem, MemComponent
from kivent_core.systems.position_systems cimport PositionStruct2D
from kivent_core.systems.rotate_systems cimport RotateStruct2D
from cpython cimport bool


ctypedef struct AttachmentStruct2D:
    unsigned int entity_id
    unsigned int parent_id
    float offset_x
    float offset_y
    float r
    PositionStruct2D *_pos_struct
    RotateStruct2D *_rot_struct

cdef class AttachmentComponent2D(MemComponent):
    pass

cdef class AttachmentSystem2D(StaticMemGameSystem):
    cdef dict attached_entities