# distutils: language = c++
from kivent_core.systems.staticmemgamesystem cimport StaticMemGameSystem, MemComponent
from kivent_core.systems.position_systems cimport PositionStruct2D
from kivent_core.systems.rotate_systems cimport RotateStruct2D
from libcpp.unordered_set cimport unordered_set
from cython cimport bint

ctypedef struct SocketStruct:
    unsigned int entity_id
    unordered_set[unsigned int] *children
    SocketStruct *_parent_socket

cdef class SocketComponent(MemComponent):
    pass

cdef class SocketSystem(StaticMemGameSystem):
    cdef unordered_set[unsigned int] root_nodes
    cdef _attach_child(self, SocketStruct* parent_socket, unsigned int child_id)
    cdef _detach_child(self, SocketStruct* parent_socket, unsigned int child_id)

ctypedef struct AttachmentStruct2D:
    unsigned int entity_id
    float offset_x
    float offset_y
    float r
    PositionStruct2D *_pos_struct
    RotateStruct2D *_rot_struct
    SocketStruct *_parent_socket

cdef class AttachmentComponent2D(MemComponent):
    pass

cdef class AttachmentSystem2D(StaticMemGameSystem):
    pass