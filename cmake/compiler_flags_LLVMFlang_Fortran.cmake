# Precision-based Fortran compiler flags
set(r8_flags "-fdefault-real-8") # Fortran flags for 64BIT precision
set(r4_flags "-fdefault-real-4") # Fortran flags for 32BIT precision

# LLVMFlang Fortran
set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -ffree-line-length-none")

set(CMAKE_Fortran_FLAGS_RELEASE "-O2")
set(CMAKE_Fortran_FLAGS_DEBUG "-O0 -g")

set(CMAKE_Fortran_LINK_FLAGS "")
