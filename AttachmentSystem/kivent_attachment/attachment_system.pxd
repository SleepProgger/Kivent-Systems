# distutils: language = c++
from kivent_core.systems.staticmemgamesystem cimport StaticMemGameSystem, MemComponent
from kivent_core.systems.position_systems cimport PositionStruct2D
from kivent_core.systems.rotate_systems cimport RotateStruct2D

from libcpp.set cimport set as cpp_set
from libcpp.unordered_set cimport unordered_set
from libcpp.queue cimport queue as cpp_queue
from libcpp.stack cimport stack
from libcpp.vector cimport vector
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
    cdef unsigned int _state
    cdef stack[RelationStruct*] _child_stack
    cdef RelationStruct* _attach_child(self, RelationStruct* parent_socket,
                       RelationStruct *child_socket) except NULL
    cdef RelationStruct* _attach_child_by_id(self, unsigned int parent_id,
                             unsigned int child_id) except NULL
    cdef unsigned int _detach_child(self, RelationStruct* parent_socket) except 0
    cdef unsigned int _detach_child_by_id(self, unsigned int child_id) except 0


ctypedef struct AttachmentStruct2D:
    unsigned int entity_id
    unsigned int components_index

cdef class AttachmentComponent2D(MemComponent):
    pass

cdef class AttachmentSystem2D(StaticMemGameSystem):
    cdef vector[RelationStruct*] _work_queue
    cdef object _system_names
    cdef unsigned int _parent_offset
    cdef unsigned int _last_socket_state
    cdef unsigned int _update(self, float dt,
            vector[RelationStruct*] *work_queue) except 0
    cdef unsigned int _init_component(self, unsigned entity_id,
            unsigned int component_index,
            unsigned int components_index) except 0
    
cdef class LocalPositionSystem2D(AttachmentSystem2D):
    pass
    