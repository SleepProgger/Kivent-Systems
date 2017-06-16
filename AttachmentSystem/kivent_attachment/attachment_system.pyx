# distutils: language = c++
# cython: embedsignature=True
# cython: profile=True
from kivy.properties import (
    BooleanProperty, StringProperty, NumericProperty, ListProperty, ObjectProperty
    )
from kivent_core.managers.entity_manager cimport EntityManager
from kivent_core.managers.system_manager cimport SystemManager 
from kivent_core.systems.staticmemgamesystem cimport StaticMemGameSystem, MemComponent
from kivent_core.memory_handlers.zone cimport MemoryZone
from kivent_core.memory_handlers.indexing cimport IndexedMemoryZone
from kivent_core.systems.position_systems cimport PositionStruct2D
from kivent_core.systems.rotate_systems cimport RotateStruct2D
from kivy.factory import Factory
from kivent_core.systems.position_systems cimport PositionComponent2D, PositionSystem2D
from kivent_core.systems.rotate_systems cimport RotateComponent2D, RotateSystem2D
from libc.math cimport sin, cos


cdef class SocketComponent(MemComponent):
    '''
    The SocketComponent holds a list of all entities attached to the
    entity holding this component.
    
    Its main use is to automatically remove all attached entities
    when the entity is removed from the gameworld.

    **Attributes:**
        **entity_id** (unsigned int): The entity_id this component is currently
        associated with. Will be <unsigned int>-1 if the component is
        unattached.

        **children** (list): A list of all entity_ids of the attached entities.
    '''
    property entity_id:
        def __get__(self):
            cdef SocketStruct* data = <SocketStruct*>self.pointer
            return data.entity_id
    property children:
        def __get__(self):
            cdef SocketStruct* data = <SocketStruct*>self.pointer
            return list(x.first[0] for x in data.children[0])

cdef class SocketSystem(StaticMemGameSystem):
    '''
    Processing Depends only on itself.
    
    A flexible SocketSystem which can be used by different GameSystems
    which need to attach entities to others in one way or another.
    Currently it is only used by the AttachmentSystem2D.
    
    Attached childrens are automatically removed when the parent
    is removed.
    
    For entities with a socket AND attachment component the socket component
    need to be initialized BEFORE the attachment.
    
    **Attributes: (Cython Access Only):
        **root_nodes** (unordered_set[SocketStruct*]): All sockets which
        aren't itself children of other sockets.
        It is usefull if you want to iterate over the attachment tree
        from top to bottom (see AttachmentSystem2D for an example).
    '''
    type_size = NumericProperty(sizeof(SocketStruct))
    component_type = ObjectProperty(SocketComponent)
    updateable = BooleanProperty(False)
    processor = BooleanProperty(False)
    system_names = ListProperty(['socket'])
    system_id = StringProperty('socket')
    
    def __init__(self, **kwargs):
        super(SocketSystem, self).__init__(**kwargs)
        
    def init_component(self, unsigned int component_index, 
        unsigned int entity_id, str zone, args):
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef SocketStruct* pointer = <SocketStruct*>memory_zone.get_pointer(
                component_index)
        pointer.entity_id = entity_id
        pointer.children = new unordered_map[unsigned int*, unsigned int]()
        pointer._parent_socket = NULL
        cdef IndexedMemoryZone entities = self.gameworld.entities
        cdef unsigned int* entity = <unsigned int*>entities.get_pointer(entity_id)
        self.root_nodes.insert(pointer)
    
    cdef _attach_child(self, SocketStruct* parent_socket, unsigned int child_id,
                        unsigned int user_data):
        '''
        Register a child as attachment of the parent_socket.
        Should only be used from AttachmentSystems init_component method.        
        
        **Parameter:
            **parent_socket** (SocketStruct*)
            
            **child_id** (unsigned int): The entity_id of the child to attach.
            
            **user_data** (unsigned int): Can be used to save an attachment
            specific index.
        '''
        cdef MemoryZone socket_memory = self.imz_components.memory_zone
        cdef IndexedMemoryZone entities = self.gameworld.entities
        cdef unsigned int system_index = self.system_index
        cdef unsigned int* entity = <unsigned int*>entities.get_pointer(child_id)
        cdef SocketStruct* child_socket
        cdef unsigned int c_index
        c_index = entity[system_index + 1] 
        if c_index != <unsigned int>-1:
            child_socket = <SocketStruct*> socket_memory.get_pointer(c_index)
            child_socket._parent_socket = parent_socket
            self.root_nodes.erase(child_socket)
        parent_socket.children[0].insert(_AttachmentPair(entity, user_data))
            
    cdef _detach_child(self, SocketStruct* parent_socket, unsigned int child_id):
        '''
        Deregister an attachment.
        Should only be used from AttachmentSystems remove_component method.        
        
        **Parameter:
            **parent_socket** (SocketStruct*)
            
            **child_id** (unsigned int): The entity_id of the child to attach.
        '''
        cdef MemoryZone socket_memory = self.imz_components.memory_zone
        cdef IndexedMemoryZone entities = self.gameworld.entities
        cdef unsigned int system_index = self.system_index
        cdef unsigned int* entity = <unsigned int*>entities.get_pointer(child_id)
        cdef SocketStruct* child_socket
        cdef unsigned int c_index
        c_index = entity[system_index + 1]
        if c_index != <unsigned int>-1:
            child_socket = <SocketStruct*> socket_memory.get_pointer(c_index)
            child_socket._parent_socket = NULL
            self.root_nodes.insert(child_socket)
        parent_socket.children[0].erase(entity)
        
    def remove_component(self, unsigned int component_index):
        cdef MemoryZone socket_memory = self.imz_components.memory_zone
        cdef SocketStruct* pointer = <SocketStruct*>socket_memory.get_pointer(
            component_index)
        cdef unsigned int child_id
        gameworld = self.gameworld
        remove_entity = self.gameworld.remove_entity
        # We need to remove all children recursive, but due to recursion limit
        # we replace the recursion with a stack based approach.
        cdef IndexedMemoryZone entities = gameworld.entities
        cdef unsigned int socket_index = self.system_index
        cdef stack[SocketStruct*] child_stack = self._child_stack
        cdef SocketStruct* cur_socket
        cdef unsigned int child_c_index
        cdef unsigned int* entity
        cdef _AttachmentPair child_pair
        child_stack.push(pointer)
        while child_stack.size() > 0:
            cur_socket = child_stack.top()
            if cur_socket.children[0].size() == 0:
                child_stack.pop()
                if cur_socket != pointer:
                    remove_entity(cur_socket.entity_id)
                continue
            for child_pair in cur_socket.children[0]:
                entity = child_pair.first
                child_c_index = entity[socket_index + 1]
                if child_c_index == <unsigned int>-1:
                    remove_entity(entity[0])
                    continue
                cur_socket = <SocketStruct*>socket_memory.get_pointer(
                    child_c_index)
                child_stack.push(cur_socket)
        pointer.children[0].clear()
        del pointer.children
        self.root_nodes.erase(pointer)
        super(SocketSystem, self).remove_component(component_index)
        
    def clear_component(self, unsigned int component_index):
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef SocketStruct* pointer = <SocketStruct*>memory_zone.get_pointer(
            component_index)
        pointer.entity_id = -1
        pointer._parent_socket = NULL
        
Factory.register('SocketSystem', cls=SocketSystem)
        
        
cdef class AttachmentComponent2D(MemComponent):
    '''
    The AttachmentComponent2D is associated with the AttachmentSystem2D.
    It holds the offset and rotation relative to the parent entity.

    **Attributes:**
        **entity_id** (unsigned int): The entity_id this component is currently
        associated with. Will be <unsigned int>-1 if the component is
        unattached.

        **parent_id** (unsigned int): The entity_id of the parent entity.
        
        **offset_x** (float): The x offset relative to the parent.
        
        **offset_y** (float): The y offset relative to the parent.
        
        **offset** (tuple): The offset (x,y) relative to the parent as tuple.
        
        **r** (float): The rotation relative to the parent.
    '''
    property entity_id:
        def __get__(self):
            cdef AttachmentStruct2D* data = <AttachmentStruct2D*>self.pointer
            return data.entity_id
        
    property parent_id:
        def __get__(self):
            cdef AttachmentStruct2D* data = <AttachmentStruct2D*>self.pointer
            return data._parent_socket.entity_id
        
    property offset_x:
        def __get__(self):
            cdef AttachmentStruct2D* data = <AttachmentStruct2D*>self.pointer
            return data.offset_x
        def __set__(self, float value):
            cdef AttachmentStruct2D* data = <AttachmentStruct2D*>self.pointer
            data.offset_x = value
            
    property offset_y:
        def __get__(self):
            cdef AttachmentStruct2D* data = <AttachmentStruct2D*>self.pointer
            return data.offset_y
        def __set__(self, float value):
            cdef AttachmentStruct2D* data = <AttachmentStruct2D*>self.pointer
            data.offset_y = value
            
    property r:
        def __get__(self):
            cdef AttachmentStruct2D* data = <AttachmentStruct2D*>self.pointer
            return data.r
        def __set__(self, float value):
            cdef AttachmentStruct2D* data = <AttachmentStruct2D*>self.pointer
            data.r = value
            
    property offset:
        def __get__(self):
            cdef AttachmentStruct2D* data = <AttachmentStruct2D*>self.pointer
            return (data.offset_x, data.offset_y)
        def __set__(self, tuple value):
            if len(value) != 2:
                raise ValueError("AttachmentComponent2D.offset need to be a tuple of 2 elements.")
            cdef AttachmentStruct2D* data = <AttachmentStruct2D*>self.pointer
            data.offset_x = value[0]
            data.offset_y = value[1]
            
            

cdef class AttachmentSystem2D(StaticMemGameSystem):
    '''
    Processing Depends On: AttachmentSystem2D, PositionSystem2D, RotateSystem2D,

    The AttachmentSystem2D allows to attach entities to other entities.
    Entities can only be attached to entities owning a SocketComponent.

    Local coordinates (offset) and local rotation (r) are available.

    Be sure to set 'socket_system' to the system_id of the SocketSystem 
    you want to attach to.

    For entities with a socket AND attachment component the socket component
    need to be initialized BEFORE the attachment.

    **Attributes:**

        **renderer_name** (StringProperty): The system_id of the
        PartclesRenderer the particles will use.

        **particle_zone** (StringProperty): The zone in memory particles will
        be created in.

    '''

    type_size = NumericProperty(sizeof(AttachmentStruct2D))
    component_type = ObjectProperty(AttachmentComponent2D)
    updateable = BooleanProperty(True)
    processor = BooleanProperty(True)
    system_names = ListProperty(['attachment', 'position', 'rotate'])
    system_id = StringProperty('attachment')
    socket_system = StringProperty('socket')
    
    def __init__(self, **kwargs):
        super(AttachmentSystem2D, self).__init__(**kwargs)
    
    def attach_entity(self, unsigned int entity_id, str zone, **kwargs):
        return self.create_component(entity_id, zone, kwargs)
    
    def detatch_entity(self, unsigned int entity_id):
        cdef unsigned int system_index = self.system_index
        cdef IndexedMemoryZone entities = self.gameworld.entities
        cdef unsigned int *entity = <unsigned int*>entities.get_pointer(entity_id)
        self.remove_component( entity[system_index + 1] )    
    
    def init_component(self, unsigned int component_index, 
        unsigned int entity_id, str zone, dict args):
        # TODO: raise error if entity doesn't have system
        if not 'parent' in args:
            raise ValueError("Attachment need parent entity_id.")
        cdef MemoryZone attachment_memory = self.imz_components.memory_zone
        cdef AttachmentStruct2D* pointer = <AttachmentStruct2D*>attachment_memory.get_pointer(
            component_index)
        cdef unsigned int parent_id = args['parent']
        pointer.entity_id = entity_id
        pointer.offset_x = args.get('offset_x', 0)
        pointer.offset_y = args.get('offset_y', 0)
        pointer.r = args.get('r', 0)
        # Get pointers to parent components
        cdef SystemManager system_manager = self.gameworld.system_manager
        cdef str pos_name = args.get('position_system', 'position')
        cdef str rot_name = args.get('rotate_system', 'rotate')    
        cdef str socket_name = self.socket_system
        cdef PositionSystem2D position_system = system_manager[pos_name]
        cdef RotateSystem2D rotate_system = system_manager[rot_name]
        cdef SocketSystem socket_system = system_manager[socket_name]
        cdef unsigned int pos_index = system_manager.get_system_index(
            pos_name)
        cdef unsigned int rot_index = system_manager.get_system_index(
            rot_name)
        cdef unsigned int socket_index = system_manager.get_system_index(
            socket_name)
        cdef MemoryZone pos_memory = position_system.imz_components.memory_zone
        cdef MemoryZone rot_memory = rotate_system.imz_components.memory_zone
        cdef MemoryZone socket_memory = socket_system.imz_components.memory_zone
        cdef IndexedMemoryZone entities = self.gameworld.entities
        cdef unsigned int* entity = <unsigned int*>entities.get_pointer(parent_id) 
        pointer._pos_struct = <PositionStruct2D*>pos_memory.get_pointer(
            entity[pos_index + 1])
        pointer._rot_struct = <RotateStruct2D*>rot_memory.get_pointer(
            entity[rot_index + 1])
        pointer._parent_socket = <SocketStruct*>socket_memory.get_pointer(
            entity[socket_index + 1])
        cdef unsigned int ent_comps_ind = self.entity_components.add_entity(
            entity_id, zone)
        socket_system._attach_child(pointer._parent_socket, entity_id, ent_comps_ind)
                 
    def remove_component(self, unsigned int component_index):
        cdef SystemManager system_manager = self.gameworld.system_manager
        cdef SocketSystem socket_system = system_manager[self.socket_system] 
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef AttachmentStruct2D* pointer = <AttachmentStruct2D*>memory_zone.get_pointer(
            component_index)
        cdef unsigned int entity_id = pointer.entity_id
        socket_system._detach_child(pointer._parent_socket, entity_id)
        self.entity_components.remove_entity(entity_id)
        super(AttachmentSystem2D, self).remove_component(component_index) 

    def clear_component(self, unsigned int component_index):
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef AttachmentStruct2D* pointer = <AttachmentStruct2D*>memory_zone.get_pointer(
            component_index)
        pointer.entity_id = -1
        pointer._pos_struct = NULL
        pointer._rot_struct = NULL
        pointer._parent_socket = NULL

    def update(self, dt):
        cdef unsigned int component_count = self.entity_components.count
        cdef void** component_data = <void**>(
            self.entity_components.memory_block.data)
        cdef float sn, cs
        cdef SystemManager system_manager = self.gameworld.system_manager
        cdef SocketSystem socket_system = system_manager[self.socket_system]
        cdef MemoryZone socket_memory = socket_system.imz_components.memory_zone
        cdef unsigned int socket_index, attachment_index
        socket_index = socket_system.system_index + 1
        attachment_index = self.system_index + 1
        cdef unsigned int *entity
        cdef unsigned int real_index
        cdef AttachmentStruct2D *attachment_struct
        cdef PositionStruct2D *position_struct
        cdef RotateStruct2D *rotate_struct
        cdef PositionStruct2D *p_position_struct
        cdef RotateStruct2D *p_rotate_struct
        cdef SocketStruct *socket_struct
        cdef _AttachmentPair child_pair
        # We need to update the values in the correct order.
        # Init with all root nodes.
        cdef cpp_queue[_AttachmentPair] work_queue = self._work_queue
        for socket_struct in socket_system.root_nodes:
            for child_pair in socket_struct.children[0]:
                work_queue.push(child_pair)
        while work_queue.size() > 0:
            child_pair = work_queue.front()
            entity = child_pair.first
            real_index = child_pair.second * component_count
            work_queue.pop()
            if entity[socket_index] != <unsigned int>-1:
                socket_struct = <SocketStruct*>socket_memory.get_pointer(
                    entity[socket_index])
                for child_pair in socket_struct.children[0]:
                    work_queue.push(child_pair)
            # This entity might be from another attachment system. 
            if entity[attachment_index] == <unsigned int>-1:
                continue
            attachment_struct = <AttachmentStruct2D*>component_data[real_index + 0]
            position_struct = <PositionStruct2D*>component_data[real_index + 1]
            rotate_struct = <RotateStruct2D*>component_data[real_index + 2]
            p_position_struct = attachment_struct._pos_struct
            p_rotate_struct = attachment_struct._rot_struct
            cs = cos(p_rotate_struct.r)
            sn = sin(p_rotate_struct.r)
            position_struct.x = p_position_struct.x + (
                attachment_struct.offset_x * cs - attachment_struct.offset_y * sn)
            position_struct.y = p_position_struct.y + (
                attachment_struct.offset_x * sn + attachment_struct.offset_y * cs)
            rotate_struct.r = p_rotate_struct.r + attachment_struct.r
        
Factory.register('AttachmentSystem2D', cls=AttachmentSystem2D)