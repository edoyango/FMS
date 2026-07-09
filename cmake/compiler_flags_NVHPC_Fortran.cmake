# Precision-based Fortran compiler flags
set(r8_flags "-r8") # Fortran flags for 64BIT precision

# NVHPC Fortan
set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} ")

# GPU offload flags, enabled via -DFMS_OMPOFFLOAD=ON
if(FMS_OMPOFFLOAD)
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -Mnovect -Mnofma -mp=gpu -acc=gpu -gpu=mem:separate")
endif()

set(CMAKE_Fortran_FLAGS_RELEASE "-O3")

set(CMAKE_Fortran_FLAGS_DEBUG "-O0" )
# -g can cause bugs, see: https://forums.developer.nvidia.com/t/bug-compiling-with-g-o0-produces-a-compute-sanitizer-error-removing-g-removes-the-error/341478
# not sure if this is only on GPUs

set(CMAKE_Fortran_LINK_FLAGS "" )
