# cython: profile=True
# cython: embedsignature=True
from kivy.properties import (
    BooleanProperty, StringProperty, NumericProperty, ListProperty, ObjectProperty
    )
from kivent_core.systems.staticmemgamesystem cimport StaticMemGameSystem, MemComponent
from kivent_core.memory_handlers.zone cimport MemoryZone
from kivent_core.systems.position_systems cimport PositionStruct2D
from kivent_core.systems.rotate_systems cimport RotateStruct2D
from kivy.factory import Factory
from kivent_core.systems.position_systems cimport PositionComponent2D
from kivent_core.systems.rotate_systems cimport RotateComponent2D
from libc.math cimport sin, cos
from cython cimport bint


cdef class AttachmentSystem2D(StaticMemGameSystem):
    '''
    Processing Depends On: PositionSystem2D, RotateSystem2D
    '''

    type_size = NumericProperty(sizeof(AttachmentStruct2D))
    component_type = ObjectProperty(AttachmentComponent2D)
    updateable = BooleanProperty(True)
    processor = BooleanProperty(True)    
    system_names = ListProperty(['attachment_system', 'position', 'rotate'])
    system_id = StringProperty('attachment_system')
    
    
    def __init__(self, **kwargs):
        super(AttachmentSystem2D, self).__init__(**kwargs)
        self.attached_entities = dict()
    
    def init_component(self, unsigned int component_index, 
        unsigned int entity_id, str zone, dict args):
        if not 'parent' in args:
            raise ValueError("Attachment need parent entity_id.") # TODO: which exception to use ?
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef AttachmentStruct2D* pointer = <AttachmentStruct2D*>memory_zone.get_pointer(
            component_index)
        pointer.entity_id = entity_id
        pointer.parent_id = args['parent']
        pointer.offset_x = args.get('offset_x', 0)
        pointer.offset_y = args.get('offset_y', 0)
        pointer.r = args.get('r', 0)
        cdef unsigned int ent_comps_ind = self.entity_components.add_entity(
            entity_id, zone)
        # TODO: do this properly in cython
        cdef str pos_system = args.get('position_system', 'position')
        cdef str rot_system = args.get('rotate_system', 'rotate')    
        cdef PositionComponent2D pos_comp = getattr(self.gameworld.entities[pointer.parent_id], pos_system)     
        cdef RotateComponent2D rot_comp = getattr(self.gameworld.entities[pointer.parent_id], rot_system)     
        pointer._pos_struct = <PositionStruct2D*>pos_comp.pointer
        pointer._rot_struct = <RotateStruct2D*>rot_comp.pointer
        
        if not pointer.parent_id in self.attached_entities:
            self.attached_entities[pointer.parent_id] = dict()
        self.attached_entities[pointer.parent_id][entity_id] = component_index
            
    def detatch_entities(self, unsigned int entity_id, bint delete_childs=True):
        '''
        Detatches all currently attached entities from 
        the given parent entity.
        If **delete_childs** is set to True remove the children.
        
        Returns False if the entity doesn't exists or has no attached children. 
        '''
        cdef dict children
        cdef unsigned int child_id, component_index
        if not entity_id in self.attached_entities:
            return False
        children = self.attached_entities[entity_id]
        if len(children) == 0:
            return False
        remove_entity = self.gameworld.remove_entity
        while children:
            child_id, component_index = children.popitem()
            if delete_childs:
               remove_entity(child_id)
            else:
                self.clear_component(component_index)
        del self.attached_entities[entity_id]
        return True
                 
    def remove_component(self, unsigned int component_index):
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef AttachmentStruct2D* pointer = <AttachmentStruct2D*>memory_zone.get_pointer(
            component_index)
        cdef unsigned int entity_id = pointer.entity_id
        cdef unsigned int parent_id = pointer.parent_id
        if parent_id in self.attached_entities:
            self.attached_entities[parent_id].pop(entity_id, 0)
        self.entity_components.remove_entity(entity_id)
        super(AttachmentSystem2D, self).remove_component(component_index) 

    def clear_component(self, unsigned int component_index):
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef AttachmentStruct2D* pointer = <AttachmentStruct2D*>memory_zone.get_pointer(
            component_index)
        pointer.entity_id = -1

    def update(self, dt):
        cdef void** component_data = <void**>(
            self.entity_components.memory_block.data)
        cdef unsigned int component_count = self.entity_components.count
        cdef unsigned int count = self.entity_components.memory_block.count
        cdef unsigned int i, real_index
        cdef AttachmentStruct2D *attachment_struct
        
        cdef PositionStruct2D *position_struct
        cdef RotateStruct2D *rotate_struct
        cdef PositionStruct2D *p_position_struct
        cdef RotateStruct2D *p_rotate_struct
        cdef float sn, cs
        
        remove_entity = self.gameworld.remove_entity
        for i in range(count):
            real_index = i*component_count
            if component_data[real_index] == NULL:
                continue            
            attachment_struct = <AttachmentStruct2D*>component_data[real_index + 0]
            if attachment_struct.entity_id == <unsigned int>-1:
                continue
            if attachment_struct.parent_id == <unsigned int>-1:
                continue
            position_struct = <PositionStruct2D*>component_data[real_index + 1]
            rotate_struct = <RotateStruct2D*>component_data[real_index + 2]
            p_position_struct = attachment_struct._pos_struct
            p_rotate_struct = attachment_struct._rot_struct
            # You should always detach childrens when removing the parent.
            # As failsafe we auto remove children if the parent was removed,
            # but do NOT rely on it. 
            if (p_position_struct.entity_id == -1
                 or p_rotate_struct.entity_id == -1):
                remove_entity(attachment_struct.entity_id)
                continue
            cs = cos(p_rotate_struct.r)
            sn = sin(p_rotate_struct.r)
            position_struct.x = p_position_struct.x + (attachment_struct.offset_x * cs - attachment_struct.offset_y * sn)
            position_struct.y = p_position_struct.y + (attachment_struct.offset_x * sn + attachment_struct.offset_y * cs)
            rotate_struct.r = p_rotate_struct.r + attachment_struct.r            
            
                
Factory.register('AttachmentSystem2D', cls=AttachmentSystem2D)