# distutils: language = c++
from kivent_core.systems.staticmemgamesystem cimport StaticMemGameSystem, MemComponent
from kivent_core.systems.position_systems cimport PositionStruct2D
from kivent_core.systems.rotate_systems cimport RotateStruct2D

from libcpp.set cimport set as cpp_set
from libcpp.unordered_set cimport unordered_set
from libcpp.queue cimport queue as cpp_queue
from libcpp.stack cimport stack
from cython cimport bint


ctypedef struct RelationStruct:
    unsigned int entity_id
    cpp_set[RelationStruct*] *children
    RelationStruct *parent
    unsigned int user_data    
    
cdef class RelationComponent(MemComponent):
    pass

cdef class RelationSystem(StaticMemGameSystem):
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

cdef class AttachmentComponent2D(MemComponent):
    pass

cdef class AttachmentSystem2D(StaticMemGameSystem):
    cdef cpp_queue[RelationStruct*] _work_queue
    #cdef do_stuff(self, unsigned int index, void** component_data)
    
    