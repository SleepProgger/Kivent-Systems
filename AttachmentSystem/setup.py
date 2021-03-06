from os import environ, remove
from platform import uname
from os.path import join, isfile, exists
from distutils.core import setup
from distutils.extension import Extension
import kivy
from subprocess import check_output

try:
    from Cython.Build import cythonize
    from Cython.Distutils import build_ext

    have_cython = True
except ImportError:
    have_cython = False
import sys

platform = sys.platform

cstdarg = '-std=gnu99'
#cstdarg = '-lstdc++'
libraries = ['GL']
extra_compile_args = []
extra_link_args = []
global_include_dirs = []
library_dirs = []
DEBUG = False

# Copied from kivent.core. Lets just hope it works for all platforms
if environ.get('NDKPLATFORM') and environ.get('LIBLINK'):
    platform = 'android'
    libraries = ['GLESv2']
elif environ.get('KIVYIOSROOT'):
    platform = 'ios'
    libraries = ['GLESv2']
    sysroot = environ.get('IOSSDKROOT', environ.get('SDKROOT'))
    global_include_dirs = [sysroot]
    extra_compile_args = ['-isysroot', sysroot]
    extra_link_args = ['-isysroot', sysroot, '-framework', 'OpenGLES']
elif exists('/opt/vc/include/bcm_host.h'):
    platform = 'rpi'
    global_include_dirs = ['/opt/vc/include',
                           '/opt/vc/include/interface/vcos/pthreads',
                           '/opt/vc/include/interface/vmcs_host/linux']
    library_dirs = ['/opt/vc/lib']
    libraries = ['bcm_host', 'EGL', 'GLESv2']
elif exists('/usr/lib/arm-linux-gnueabihf/libMali.so'):
    platform = 'mali'
    global_include_dirs = ['/usr/include']
    library_dirs = ['/usr/lib/arm-linux-gnueabihf']
    libraries = ['GLESv2']
elif platform == 'win32':
    cstdarg = '-std=gnu99'
    libraries = ['opengl32', 'glu32', 'glew32']
elif platform.startswith('freebsd'):
    localbase = environ.get('LOCALBASE', '/usr/local')
    global_include_dirs = [join(localbase, 'include')]
    extra_link_args = ['-L', join(localbase, 'lib')]
elif platform.startswith('openbsd'):
    global_include_dirs = ['/usr/X11R6/include']
    extra_link_args = ['-L', '/usr/X11R6/lib']
elif platform == 'darwin':
    if sys.maxsize > 2 ** 32:
        osx_arch = 'x86_64'
    else:
        osx_arch = 'i386'
    v = uname()
    if v[2] >= '13.0.0':
        import platform as _platform

        xcode_dev = check_output(['xcode-select', '-p']).decode().strip()
        sdk_mac_ver = '.'.join(_platform.mac_ver()[0].split('.')[:2])
        sysroot = join(xcode_dev,
                       'Platforms/MacOSX.platform/Developer/SDKs',
                       'MacOSX{}.sdk'.format(sdk_mac_ver),
                       'System/Library/Frameworks')
    else:
        sysroot = ('/System/Library/Frameworks/'
                   'ApplicationServices.framework/Frameworks')
    extra_compile_args = ['-F' + sysroot, '-arch', osx_arch]
    extra_link_args = ['-F' + sysroot, '-arch', osx_arch,
                       '-framework', 'OpenGL']
    libraries = []

do_clear_existing = True



prefixes = {
    'attachment_system': 'kivent_attachment.',
}

file_prefixes = {
    'attachment_system': 'kivent_attachment/',
}

modules = {
    'attachment_system': ['attachment_system'],
    #'color_rotate_scale_renderer.color_rotate_scale_renderer': ['color_rotate_scale_renderer/color_rotate_scale_renderer.pyx']
}
#modules_c = {
#    #'color_rotate_scale_renderer.color_rotate_scale_renderer': ['color_rotate_scale_renderer/color_rotate_scale_renderer.c']
#}

real_modules = {}
real_modules_c = {}
check_for_removal = []

for name in modules:
    file_prefix = file_prefixes[name]
    prefix = prefixes[name]
    module_files = modules[name]
    for module_name in module_files:
        real_modules[prefix + module_name] = [file_prefix + module_name + '.pyx']
        real_modules_c[prefix + module_name] = [file_prefix + module_name + '.c', file_prefix + module_name + '.cpp']
        check_for_removal.append(file_prefix + module_name + '.c')
        check_for_removal.append(file_prefix + module_name + '.cpp')
        
print real_modules
print real_modules_c
print check_for_removal

#exit(1)

def build_ext(ext_name, files, include_dirs=[]):
    print(global_include_dirs + include_dirs)
    return Extension(ext_name, files, global_include_dirs + include_dirs,
                     extra_compile_args=[cstdarg, '-ffast-math', ] + extra_compile_args,
                     libraries=libraries, extra_link_args=extra_link_args,
                     library_dirs=library_dirs,
                     language=None)
    
extensions = []
cmdclass = {}
    
def build_extensions_for_modules_cython(ext_list, modules):
    ext_a = ext_list.append
    for module_name in real_modules:
        ext = build_ext(module_name, real_modules[module_name], include_dirs=kivy.get_includes())
        if environ.get('READTHEDOCS', None) == 'True':
            ext.pyrex_directives = {'embedsignature': True}
        ext_a(ext)
    return cythonize(ext_list, compiler_directives={'profile': DEBUG})

def build_extensions_for_modules(ext_list, modules):
    ext_a = ext_list.append
    for module_name in real_modules:
        ext = build_ext(module_name, real_modules[module_name], include_dirs=kivy.get_includes())
        if environ.get('READTHEDOCS', None) == 'True':
            ext.pyrex_directives = {'embedsignature': True}
        ext_a(ext)
    return ext_list

if have_cython:
    if do_clear_existing:
        for file_name in check_for_removal:
            if isfile(file_name):
                remove(file_name)
    extensions = build_extensions_for_modules_cython(
        extensions, real_modules)
else:
    extensions = build_extensions_for_modules(extensions, 
        real_modules_c)

setup(
    name='KivEnt attachment system',
    description='''A Gamesystem to attach entities to others.''',
    version='0.1',
    author='SleepProgger',
    author_email='kivent@gnutp.com',
    ext_modules=extensions,
    cmdclass=cmdclass,
    packages=[
        'kivent_attachment',
        ],
)