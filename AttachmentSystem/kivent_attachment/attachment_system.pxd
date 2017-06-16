# distutils: language = c++
# cython: profile=True
from kivent_core.systems.staticmemgamesystem cimport StaticMemGameSystem, MemComponent
from kivent_core.systems.position_systems cimport PositionStruct2D
from kivent_core.systems.rotate_systems cimport RotateStruct2D
from libcpp.unordered_map cimport unordered_map
from libcpp.unordered_set cimport unordered_set
from libcpp.queue cimport queue as cpp_queue
from libcpp.stack cimport stack
from libcpp.pair cimport pair
from cython cimport bint

# A "tuple" containing a pointer to an entities component index memory
# and its corresponding user_data.
# Returned by SocketStruct.children. 
ctypedef pair[unsigned int*, unsigned int] _AttachmentPair

ctypedef struct SocketStruct:
    unsigned int entity_id
    unordered_map[unsigned int*, unsigned int] *children
    SocketStruct *_parent_socket

cdef class SocketComponent(MemComponent):
    pass

cdef class SocketSystem(StaticMemGameSystem):
    cdef unordered_set[SocketStruct*] root_nodes
    cdef stack[SocketStruct*] _child_stack
    cdef _attach_child(self, SocketStruct* parent_socket,
                       unsigned int child_id, unsigned int user_data)
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
    cdef cpp_queue[_AttachmentPair] _work_queue