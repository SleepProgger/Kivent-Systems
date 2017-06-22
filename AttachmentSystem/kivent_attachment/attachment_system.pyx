# distutils: language = c++
# cython: embedsignature=True
from kivy.properties import (
    BooleanProperty, StringProperty, NumericProperty, ListProperty, ObjectProperty
    )
from kivent_core.managers.entity_manager cimport EntityManager
from kivent_core.managers.system_manager cimport SystemManager 
from kivent_core.systems.staticmemgamesystem cimport StaticMemGameSystem, MemComponent
from kivent_core.memory_handlers.zone cimport MemoryZone
from kivent_core.memory_handlers.membuffer cimport Buffer
from kivent_core.memory_handlers.indexing cimport IndexedMemoryZone
from kivent_core.systems.position_systems cimport PositionStruct2D
from kivent_core.systems.rotate_systems cimport RotateStruct2D
from kivy.factory import Factory
from kivent_core.systems.position_systems cimport PositionComponent2D, PositionSystem2D
from kivent_core.systems.rotate_systems cimport RotateComponent2D, RotateSystem2D
from kivent_core.systems.gamesystem cimport GameSystem 
from libc.math cimport sin, cos
from Crypto.Util.number import size


cdef class RelationComponent(MemComponent):
    '''
    The RelationComponent holds a list of all entities attached to the
    entity holding this component.
    
    Its main use is to automatically remove all attached entities
    when the entity is removed from the gameworld and to iterate
    relationsship trees.

    **Attributes:**
        **entity_id** (unsigned int): The entity_id this component is currently
        associated with. Will be <unsigned int>-1 if the component is
        unattached.
        
        **parent** (unsigned int): The id of the parent or <unsigned int>-1
        if this element doesn't have a parent.        

        **children** (list): A list of all entity_ids of the attached entities.
    '''
    property entity_id:
        def __get__(self):
            cdef RelationStruct* data = <RelationStruct*>self.pointer
            return data.entity_id
        
    property parent:
        def __get__(self):
            cdef RelationStruct* data = <RelationStruct*>self.pointer
            if data.parent == NULL:
                return <unsigned int>-1
            return data.parent.entity_id
        
    property children:
        def __get__(self):
            cdef RelationStruct* data = <RelationStruct*>self.pointer
            if data.children == NULL:
                return 0
            return list(x.entity_id for x in data.children[0])


# TODO:
# - Add top down iterator for python
# - Think about exposing attach and dettach to py
cdef class RelationSystem(StaticMemGameSystem):
    '''
    Processing Depends only on itself.
    
    A flexible Relationship system which can be used by different GameSystems
    which need to attach entities to others in one way or another.
    Currently it is only used by the AttachmentSystem2D.
    
    Attached childrens are automatically removed when the parent
    is removed.
    
    For entities with a relationsship AND attachment component the relationsship
    component need to be initialized BEFORE the attachment.
    
    **Attributes: (Cython Access Only):
        **root_nodes** (unordered_set[RelationStruct*]): All sockets which
        aren't itself children of other sockets.
        It is usefull if you want to iterate over the attachment tree
        from top to bottom (see AttachmentSystem2D for an example).
        
        **_state** (unsigned int): A simple (wrap around) counter which is
        increased after every change to the relationsship tree.
        Usefull to check if the tree has changed since the last update tick
        when the iteration order is cached.
    '''
    type_size = NumericProperty(sizeof(RelationStruct))
    component_type = ObjectProperty(RelationComponent)
    updateable = BooleanProperty(False)
    processor = BooleanProperty(False)
    system_names = ListProperty(['relations'])
    system_id = StringProperty('relations')
    
    def __init__(self, **kwargs):
        super(RelationSystem, self).__init__(**kwargs)
        self._state = 0
        
    def init_component(self, unsigned int component_index, 
        unsigned int entity_id, str zone, args):
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef RelationStruct* pointer = <RelationStruct*>memory_zone.get_pointer(
                component_index)
        pointer.entity_id = entity_id
        pointer.parent = NULL
        pointer.children = NULL
        self.root_nodes.insert(pointer)
    
    cdef RelationStruct* _attach_child(self, RelationStruct* parent, RelationStruct* child) except NULL:
        '''
        Register a child as attachment of the parent_socket.
        Should only be used from AttachmentSystems init_component method.        
        
        **Parameter:
            **parent** (RelationStruct*)
            
            **child** (RelationStruct*)
        '''
        child.parent = parent
        if parent.children == NULL:
            parent.children = new cpp_set[RelationStruct*]()
        parent.children[0].insert(child)
        self.root_nodes.erase(child)
        self._state = (self._state + 1) % <unsigned int>-1
        return child
        
    cdef RelationStruct* _attach_child_by_id(self, unsigned int parent_id, unsigned int child_id) except NULL:
        cdef MemoryZone my_memory = self.imz_components.memory_zone
        cdef IndexedMemoryZone entities = self.gameworld.entities
        cdef unsigned int system_index = self.system_index + 1
        cdef unsigned int* entity = <unsigned int*>entities.get_pointer(child_id)
        cdef RelationStruct *child_struct = <RelationStruct*>my_memory.get_pointer(
            entity[system_index])
        entity = <unsigned int*>entities.get_pointer(parent_id)
        cdef RelationStruct *parent_struct = <RelationStruct*>my_memory.get_pointer(
            entity[system_index])
        return self._attach_child(parent_struct, child_struct)
    
    cdef unsigned int _detach_child(self, RelationStruct* child) except 0:
        '''
        Deregister an attachment.
        Should only be used from AttachmentSystems remove_component method.        
        
        **Parameter:
            **parent_socket** (RelationStruct*)
            
            **child_id** (unsigned int): The entity_id of the child to attach.
        '''
        child.parent.children[0].erase(child)
        self.root_nodes.insert(child)
        child.parent = NULL
        self._state = (self._state + 1) % <unsigned int>-1
        return 1
        
    cdef unsigned int _detach_child_by_id(self, unsigned int child_id) except 0:
        cdef MemoryZone my_memory = self.imz_components.memory_zone
        cdef IndexedMemoryZone entities = self.gameworld.entities
        cdef unsigned int system_index = self.system_index + 1
        cdef unsigned int* entity = <unsigned int*>entities.get_pointer(child_id)
        cdef RelationStruct *child_struct = <RelationStruct*>my_memory.get_pointer(
            entity[system_index])
        return self._detach_child(child_struct)
        
    def remove_component(self, unsigned int component_index):
        cdef MemoryZone socket_memory = self.imz_components.memory_zone
        cdef RelationStruct* pointer = <RelationStruct*>socket_memory.get_pointer(
            component_index)
        cdef unsigned int child_id
        cdef RelationStruct* cur_socket
        cdef RelationStruct* child_socket
        gameworld = self.gameworld
        remove_entity = self.gameworld.remove_entity
        # We need to remove all children recursive, but due to recursion limit
        # we replace the recursion with a stack based approach.
        cdef stack[RelationStruct*] child_stack = self._child_stack
        child_stack.push(pointer)
        while child_stack.size() > 0:
            cur_socket = child_stack.top()
            if cur_socket.children == NULL or cur_socket.children[0].size() == 0:
                child_stack.pop()
                if cur_socket != pointer:
                    remove_entity(cur_socket.entity_id)
                continue
            if cur_socket.children:
                for child_socket in cur_socket.children[0]:
                    child_stack.push(child_socket)
        if pointer.children:
            pointer.children[0].clear()
            del pointer.children
        self.root_nodes.erase(pointer)
        self._state = (self._state + 1) % <unsigned int>-1 
        super(RelationSystem, self).remove_component(component_index)
        
    def clear_component(self, unsigned int component_index):
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef RelationStruct* pointer = <RelationStruct*>memory_zone.get_pointer(
            component_index)
        pointer.entity_id = -1
        pointer.parent = NULL
        
Factory.register('RelationSystem', cls=RelationSystem)
        
        
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


cdef class AttachmentSystem2D(StaticMemGameSystem):
    '''
    Processing Depends On: AttachmentSystem2D, PositionSystem2D, RotateSystem2D,
    RelationSystem

    The AttachmentSystem2D allows to attach entities to other entities to 
    construct local coordinate systems.
    Attached entities and their parents need to own a RelationComponent.

    Local coordinates (offset) and local rotation (r) are available.

    Entities which act as parent AND child of another entity need to initialize
    the RelationComponent before the AttachmentComponent.
    '''
    # TODO: hide component from entities ?
    type_size = NumericProperty(sizeof(AttachmentStruct2D))
    component_type = ObjectProperty(AttachmentComponent2D)
    updateable = BooleanProperty(True)
    processor = BooleanProperty(True)
    system_names = ListProperty([
        # own relationsship components
        'relations',
        # own components global position
        'position', 'rotate',
    ])
    local_systems = ListProperty([
        'local_position', 'local_rotate',
    ])
    parent_systems = ListProperty([
        'position', 'rotate'
    ])
    system_id = StringProperty('attachment')
    
    def __init__(self, **kwargs):
        self._system_names = None
        self._parent_offset = len(self.system_names) + len(self.local_systems)
        self._last_socket_state = 0
        super(AttachmentSystem2D, self).__init__(**kwargs)
        
    def allocate(self, Buffer master_buffer, dict reserve_spec):
        # We use our own component as placeholder for the parent components
        # because we might not have the related parent components.
        cdef str my_component = self.system_names[0]
        self._system_names = (self.system_names + self.local_systems +
                              list(my_component for _ in self.parent_systems))
        self.system_names = list(self._system_names)
        return super(AttachmentSystem2D, self).allocate(master_buffer, reserve_spec)

    def attach_entity(self, unsigned int entity_id, str zone, **kwargs):
        return self.create_component(entity_id, zone, kwargs)
    
    def detatch_entity(self, unsigned int entity_id):
        cdef unsigned int system_index = self.system_index
        cdef IndexedMemoryZone entities = self.gameworld.entities
        cdef unsigned int *entity = <unsigned int*>entities.get_pointer(entity_id)
        self.remove_component( entity[system_index + 1] )    
    
    cdef unsigned int _init_component(self, unsigned entity_id,
                    unsigned int component_index,
                    unsigned int components_index) except 0:
        '''
        Overwrite this method if you have additional attributes in your
        AttachmenStruct. 
        '''
        cdef MemoryZone attachment_memory = self.imz_components.memory_zone
        cdef AttachmentStruct2D* pointer = <AttachmentStruct2D*>attachment_memory.get_pointer(
            component_index)
        pointer.entity_id = entity_id
        pointer.components_index = components_index
        return 1
    
    def init_component(self, unsigned int component_index, 
        unsigned int entity_id, str zone, dict args):
        if not 'parent' in args:
            raise ValueError("Attachment need parent entity_id.")
        cdef unsigned int parent_id = args['parent']
        cdef SystemManager system_manager = self.gameworld.system_manager
        cdef IndexedMemoryZone entities = self.gameworld.entities
        cdef unsigned int *parent_entity = <unsigned int*>entities.get_pointer(
            parent_id)
        if parent_entity[0] == <unsigned int>-1:
            raise ValueError("Attachments parent id invalid.")
        cdef str system_name
        cdef unsigned int system_index
        cdef StaticMemGameSystem system        
        cdef MemoryZone system_memory
        cdef unsigned int comp_index
        cdef void *pointer
        cdef unsigned int ent_comps_ind = self.entity_components.add_entity(
            entity_id, zone)
        cdef unsigned int component_count = self.entity_components.count
        cdef void** component_data = <void**>(
            self.entity_components.memory_block.data)
        cdef real_index = ent_comps_ind * component_count
        cdef unsigned int i = self._parent_offset
        for system_name in self.parent_systems:
            system = system_manager[system_name]
            system_index = system.system_index + 1
            comp_index = parent_entity[system_index]
            if comp_index == <unsigned int>-1:
                raise ValueError("Attachments parent has no '%s' component." % system_name)
            system_memory = system.imz_components.memory_zone
            pointer = system_memory.get_pointer(comp_index)
            component_data[real_index + i] = pointer
            i += 1
        cdef RelationSystem relations = system_manager[self.system_names[0]]
        cdef RelationStruct *relation_struct = relations._attach_child_by_id(
            parent_id, entity_id)
        relation_struct.user_data = ent_comps_ind
        self._init_component(entity_id, component_index, ent_comps_ind)
                 
    def remove_component(self, unsigned int component_index):
        cdef SystemManager system_manager = self.gameworld.system_manager
        cdef RelationSystem socket_system = system_manager[self.system_names[1]] 
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef unsigned int* pointer = <unsigned int*>memory_zone.get_pointer(
            component_index)
        cdef unsigned int entity_id = pointer[0]
        socket_system._detach_child_by_id(entity_id)
        self.entity_components.remove_entity(entity_id)
        super(AttachmentSystem2D, self).remove_component(component_index) 

    def clear_component(self, unsigned int component_index):
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef AttachmentStruct2D* pointer = <AttachmentStruct2D*>memory_zone.get_pointer(
            component_index)
        pointer.entity_id = -1

    cdef unsigned int _update(self, float dt, vector[RelationStruct*] *work_queue) except 0:
        cdef void** component_data = <void**>(
            self.entity_components.memory_block.data)
        cdef unsigned int component_count = self.entity_components.count
        cdef PositionStruct2D *global_pos 
        cdef PositionStruct2D *local_pos 
        cdef PositionStruct2D *parent_pos
        cdef RotateStruct2D *global_rot
        cdef RotateStruct2D *local_rot
        cdef RotateStruct2D *parent_rot
        cdef RelationStruct *parent
        cdef unsigned int real_index
        cdef float cs, sn
        for parent in work_queue[0]:
            if parent == NULL:
                continue
            real_index = parent.user_data * component_count
            global_pos = <PositionStruct2D*>component_data[real_index + 1]
            global_rot = <RotateStruct2D*>component_data[real_index + 2]
            local_pos = <PositionStruct2D*>component_data[real_index + 3]
            local_rot = <RotateStruct2D*>component_data[real_index + 4]
            parent_pos = <PositionStruct2D*>component_data[real_index + 5]
            parent_rot = <RotateStruct2D*>component_data[real_index + 6]
            cs = cos(parent_rot.r)
            sn = sin(parent_rot.r)
            global_pos.x = parent_pos.x + (
                local_pos.x * cs - local_pos.y * sn)
            global_pos.y = parent_pos.y + (
                local_pos.x * sn + local_pos.y * cs)
            global_rot.r = parent_rot.r + local_rot.r
        return 1

    def update(self, dt):
        cdef unsigned int component_count = self.entity_components.count
        cdef max_comp_index = self.entity_components.memory_block.count - 1
        cdef void** component_data = <void**>(
            self.entity_components.memory_block.data)
        cdef SystemManager system_manager = self.gameworld.system_manager
        cdef RelationSystem socket_system = system_manager[self.system_names[0]]
        cdef unsigned int user_data, real_index, entity_id
        cdef RelationStruct *parent
        cdef RelationStruct *child
        # We need to update the values in the correct order.
        # Init with all root nodes.
        # TODO: switch to static memory
        cdef vector[RelationStruct*] *work_queue = &self._work_queue
        cdef unsigned int size = 0
        cdef unsigned int pos = 0
        if socket_system._state != self._last_socket_state:
            work_queue[0].clear()
            for parent in socket_system.root_nodes:
                if parent.children == NULL:
                    continue
                for child in parent.children[0]:
                    work_queue[0].push_back(child)
                    size += 1
            while pos < size:
                parent = work_queue[0][pos]
                user_data = parent.user_data 
                if parent.children and parent.children[0].size():
                    for child in parent.children[0]:
                        work_queue[0].push_back(child)
                        size += 1
                # We need to skip sockets not part of this attachment system.
                if user_data > max_comp_index:
                    work_queue[0][pos] = NULL
                    pos += 1
                    continue
                real_index = user_data * component_count
                entity_id = (<unsigned int*>(component_data[real_index + 0]))[0]
                if entity_id != parent.entity_id:
                    work_queue[0][pos] = NULL
                pos += 1
            self._last_socket_state = socket_system._state
            print "Size:", work_queue.size()
        # Do the real calculations
        self._update(dt, work_queue)
    
Factory.register('AttachmentSystem2D', cls=AttachmentSystem2D)


cdef class LocalPositionSystem2D(AttachmentSystem2D):
    type_size = NumericProperty(sizeof(AttachmentStruct2D))
    component_type = ObjectProperty(AttachmentComponent2D)
    system_names = ListProperty([
        # own relationsship components
        'relations',
        # own components global position
        'position',
    ])
    local_systems = ListProperty([
        'local_position',
    ])
    parent_systems = ListProperty([
        'position',
    ])
    system_id = StringProperty('local_position_system')
    
    cdef unsigned int _update(self, float dt, vector[RelationStruct*] *work_queue) except 0:
        cdef void** component_data = <void**>(
            self.entity_components.memory_block.data)
        cdef unsigned int component_count = self.entity_components.count
        cdef PositionStruct2D *global_pos 
        cdef PositionStruct2D *local_pos 
        cdef PositionStruct2D *parent_pos
        cdef RelationStruct *parent
        cdef unsigned int real_index
        for parent in work_queue[0]:
            if parent == NULL:
                continue
            real_index = parent.user_data * component_count
            global_pos = <PositionStruct2D*>component_data[real_index + 1]
            local_pos = <PositionStruct2D*>component_data[real_index + 2]
            parent_pos = <PositionStruct2D*>component_data[real_index + 3]
            global_pos.x = parent_pos.x + local_pos.x
            global_pos.y = parent_pos.y + local_pos.y
        return 1

Factory.register('LocalPositionSystem2D', cls=LocalPositionSystem2D)