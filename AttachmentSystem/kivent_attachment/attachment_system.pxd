# distutils: language = c++
# cython: profile=True
from kivent_core.systems.staticmemgamesystem cimport StaticMemGameSystem, MemComponent
from kivent_core.systems.position_systems cimport PositionStruct2D
from kivent_core.systems.rotate_systems cimport RotateStruct2D
from libcpp.map cimport map as cpp_map
from libcpp.set cimport set as cpp_set
#from libcpp.unordered_map cimport unordered_map
from libcpp.unordered_set cimport unordered_set
from libcpp.queue cimport queue as cpp_queue
from libcpp.stack cimport stack
from libcpp.pair cimport pair
from cython cimport bint

# A "tuple" containing a pointer to an entities component index memory
# and its corresponding user_data.
# Returned by RelationStruct.children. 
#ctypedef pair[unsigned int*, unsigned int] _AttachmentPair

ctypedef struct RelationStruct:
    unsigned int entity_id
    cpp_set[RelationStruct*] *children
    RelationStruct *parent_socket
    unsigned int user_data

cdef class RelationComponent(MemComponent):
    pass

cdef class SocketSystem(StaticMemGameSystem):
    cdef unordered_set[RelationStruct*] root_nodes
    cdef stack[RelationStruct*] _child_stack
    cdef _attach_child(self, RelationStruct* parent_socket,
                       RelationStruct *child_socket)
    cdef _detach_child(self, RelationStruct* parent_socket)
    cdef _detach_child_by_id(self, unsigned int child_id)

ctypedef struct AttachmentStruct2D:
    unsigned int entity_id
    float offset_x
    float offset_y
    float r
    PositionStruct2D *_pos_struct
    RotateStruct2D *_rot_struct
    #RelationStruct *_parent_socket

cdef class AttachmentComponent2D(MemComponent):
    pass

cdef class AttachmentSystem2D(StaticMemGameSystem):
    cdef cpp_queue[RelationStruct*] _work_queue
    
    