!***********************************************************************
!*                             Apache License 2.0
!*
!* This file is part of the GFDL Flexible Modeling System (FMS).
!*
!* Licensed under the Apache License, Version 2.0 (the "License");
!* you may not use this file except in compliance with the License.
!* You may obtain a copy of the License at
!*
!*     http://www.apache.org/licenses/LICENSE-2.0
!*
!* FMS is distributed in the hope that it will be useful, but WITHOUT
!* WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied;
!* without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
!* PARTICULAR PURPOSE. See the License for the specific language
!* governing permissions and limitations under the License.
!***********************************************************************

!> @brief Tests send_data with on_device=.true. in the old and the modern diag_manager.
!!
!! The fields are computed on the OpenMP device. With on_device = .true. in test_diag_on_device_nml they
!! are posted from the device; otherwise they are copied back and posted from the host.
!! test_diag_on_device.sh runs both and checks that the output files are identical. The fields cover
!! 3-d and 2-d data with halos, an r4 field without halos, rmask (including one passed through a
!! pointer whose lower bound is 0), values equal to the missing value, fields without a missing value,
!! weighted time means, instantaneous values, and a static field. test_modern_diag_on_device.sh runs it
!! with the modern diag_manager, which does not accept missing values in unmasked time averages: it sets
!! f4_missing = .false., and checks with u2_missing = .true. that such data fail in both paths.
!! Four more fields are computed and kept on the host only, with host-only masks (an rmask or a logical mask,
!! 2-d and 3-d). They are posted with the same on_device, so that send_data has to copy them to the device for the
!! post. The files also have time maxima and minima.
program test_diag_on_device
  use fms_mod,          only: fms_init, fms_end, check_nml_error
  use mpp_mod,          only: input_nml_file
  use mpp_domains_mod,  only: domain2d, mpp_define_domains, mpp_get_compute_domain, mpp_get_data_domain, &
                              mpp_define_io_domain
  use diag_manager_mod, only: diag_manager_init, diag_manager_end, diag_axis_init, register_diag_field, &
                              register_static_field, send_data, diag_manager_set_time_end, diag_send_complete
  use time_manager_mod, only: time_type, set_calendar_type, set_date, set_time, JULIAN, operator(+)
  use platform_mod,     only: r4_kind, r8_kind

  implicit none

  integer, parameter :: nx = 40       !< Number of x points
  integer, parameter :: ny = 30       !< Number of y points
  integer, parameter :: nz = 3        !< Number of z points
  integer, parameter :: halo = 2      !< Halo size
  integer, parameter :: nsteps = 48   !< Number of time steps
  real(r8_kind), parameter :: missing = 1.0e20_r8_kind !< The missing value

  type(domain2d)  :: Domain           !< The domain of the data
  type(time_type) :: Time             !< The model time
  type(time_type) :: Time_step        !< The time step
  integer :: isc, iec, jsc, jec       !< Compute domain
  integer :: isd, ied, jsd, jed       !< Data domain
  integer :: id_x, id_y, id_z         !< Axis ids
  integer :: id_t3, id_u3, id_t2, id_u2, id_f4, id_static !< Field ids
  integer :: id_h3, id_h2, id_l3, id_l2 !< Ids of the fields that are only on the host
  real(r8_kind), allocatable, target :: t3(:,:,:)   !< 3-d data with halos
  real(r8_kind), allocatable, target :: u3(:,:,:)   !< 3-d data with halos and a lower-bound-0 rmask
  real(r8_kind), allocatable, target :: t2(:,:)     !< 2-d data with halos and an rmask
  real(r8_kind), allocatable, target :: u2(:,:)     !< 2-d data with halos, no mask, no missing value
  real(r4_kind), allocatable, target :: f4(:,:,:)   !< r4 data on the compute domain, some missing
  real(r8_kind), allocatable, target :: stat(:,:)   !< A static field
  real(r8_kind), allocatable, target :: mask3(:,:,:) !< 3-d mask
  real(r8_kind), allocatable, target :: mask2(:,:)   !< 2-d mask
  real(r8_kind), pointer :: pmask3(:,:,:) => null() !< mask3 with lower bounds of 0
  real(r8_kind), allocatable, target :: h3(:,:,:)    !< 3-d data that is only on the host, with an rmask
  real(r8_kind), allocatable, target :: h2(:,:)      !< 2-d data that is only on the host, with an rmask
  real(r8_kind), allocatable, target :: l3(:,:,:)    !< 3-d data that is only on the host, with a logical mask
  real(r8_kind), allocatable, target :: l2(:,:)      !< 2-d data that is only on the host, with a logical mask
  real(r8_kind), allocatable, target :: hmask3(:,:,:) !< Host-only 3-d rmask
  real(r8_kind), allocatable, target :: hmask2(:,:)   !< Host-only 2-d rmask
  logical, allocatable, target :: lmask3(:,:,:)      !< Host-only 3-d logical mask
  logical, allocatable, target :: lmask2(:,:)        !< Host-only 2-d logical mask
  real(r8_kind) :: weight     !< Averaging weight
  real(r8_kind) :: x(nx), y(ny), z(nz) !< Axis data
  logical :: used             !< Return value of send_data
  logical :: on_device = .false. !< If true, post from the device
  logical :: f4_missing = .true.  !< If true, some f4 values equal the missing value
  logical :: u2_missing = .false. !< If true, one u2 value equals the missing value
  integer :: i, j, k, n, io, ierr

  namelist /test_diag_on_device_nml/ on_device, f4_missing, u2_missing

  call fms_init
  read (input_nml_file, test_diag_on_device_nml, iostat=io)
  ierr = check_nml_error(io, 'test_diag_on_device_nml')
  call set_calendar_type(JULIAN)
  call diag_manager_init

  call mpp_define_domains((/1, nx, 1, ny/), (/1, 1/), Domain, xhalo=halo, yhalo=halo, name='test')
  call mpp_define_io_domain(Domain, (/1, 1/)) ! The modern diag_manager needs an io_domain
  call mpp_get_compute_domain(Domain, isc, iec, jsc, jec)
  call mpp_get_data_domain(Domain, isd, ied, jsd, jed)

  do i = 1, nx ; x(i) = real(i, r8_kind) ; enddo
  do j = 1, ny ; y(j) = real(j, r8_kind) ; enddo
  do k = 1, nz ; z(k) = real(k, r8_kind) ; enddo
  id_x = diag_axis_init('x', x, 'degrees_E', 'X', 'x', Domain2=Domain)
  id_y = diag_axis_init('y', y, 'degrees_N', 'Y', 'y', Domain2=Domain)
  id_z = diag_axis_init('z', z, 'm', 'Z', 'z')

  Time = set_date(2, 1, 1, 0, 0, 0)
  Time_step = set_time(3600, 0)
  call diag_manager_set_time_end(set_date(2, 1, 3, 0, 0, 0))

  id_t3 = register_diag_field('test_mod', 't3', (/id_x, id_y, id_z/), Time, 't3', 'none', missing_value=missing)
  id_u3 = register_diag_field('test_mod', 'u3', (/id_x, id_y, id_z/), Time, 'u3', 'none', missing_value=missing)
  id_t2 = register_diag_field('test_mod', 't2', (/id_x, id_y/), Time, 't2', 'none', missing_value=missing)
  id_u2 = register_diag_field('test_mod', 'u2', (/id_x, id_y/), Time, 'u2', 'none')
  id_f4 = register_diag_field('test_mod', 'f4', (/id_x, id_y, id_z/), Time, 'f4', 'none', &
                              missing_value=real(missing, r4_kind))
  id_h3 = register_diag_field('test_mod', 'h3', (/id_x, id_y, id_z/), Time, 'h3', 'none', missing_value=missing)
  id_h2 = register_diag_field('test_mod', 'h2', (/id_x, id_y/), Time, 'h2', 'none', missing_value=missing)
  id_l3 = register_diag_field('test_mod', 'l3', (/id_x, id_y, id_z/), Time, 'l3', 'none', missing_value=missing)
  id_l2 = register_diag_field('test_mod', 'l2', (/id_x, id_y/), Time, 'l2', 'none', missing_value=missing)
  id_static = register_static_field('test_mod', 'static', (/id_x, id_y/), 'static', 'none', &
                                    missing_value=missing)

  allocate(t3(isd:ied, jsd:jed, nz), u3(isd:ied, jsd:jed, nz), mask3(isd:ied, jsd:jed, nz))
  allocate(t2(isd:ied, jsd:jed), u2(isd:ied, jsd:jed), mask2(isd:ied, jsd:jed), stat(isd:ied, jsd:jed))
  allocate(f4(isc:iec, jsc:jec, nz))
  allocate(h3(isd:ied, jsd:jed, nz), l3(isd:ied, jsd:jed, nz), hmask3(isd:ied, jsd:jed, nz), lmask3(isd:ied, jsd:jed, nz))
  allocate(h2(isd:ied, jsd:jed), l2(isd:ied, jsd:jed), hmask2(isd:ied, jsd:jed), lmask2(isd:ied, jsd:jed))

  ! Land in a block, along the western edge of the compute domain, and in all halos
  mask3(:,:,:) = 0.0_r8_kind
  mask3(isc+1:iec, jsc:jec, :) = 1.0_r8_kind
  mask3(isc+10:isc+14, jsc+5:jsc+9, :) = 0.0_r8_kind
  mask2(:,:) = mask3(:,:,1)
  pmask3(0:, 0:, 1:) => mask3

  ! The host-only masks: a different pattern of land from mask3, so that they are not mistaken for it
  hmask3(:,:,:) = mask3(:,:,:)
  hmask3(isc+3:isc+6, jsc+2:jsc+4, :) = 0.0_r8_kind
  hmask2(:,:) = hmask3(:,:,1)
  lmask3(:,:,:) = hmask3(:,:,:) > 0.5_r8_kind
  lmask3(isc+20:isc+22, jsc+10:jsc+12, 2) = .false.
  lmask2(:,:) = lmask3(:,:,1)

  !$omp target enter data map(to: mask3, mask2)
  !$omp target enter data map(alloc: t3, u3, t2, u2, f4, stat)

  ! The static field
  !$omp target teams distribute parallel do collapse(2)
  do j = jsd, jed ; do i = isd, ied
    stat(i,j) = real(i, r8_kind) + 100.0_r8_kind*real(j, r8_kind)
  enddo ; enddo
  if (.not.on_device) then
    !$omp target update from(stat)
  endif
  used = send_data(id_static, stat, Time, is_in=isc-isd+1, ie_in=iec-isd+1, js_in=jsc-jsd+1, je_in=jec-jsd+1, &
                   rmask=mask2, on_device=on_device)

  do n = 1, nsteps
    Time = Time + Time_step
    weight = 1.0_r8_kind
    if (mod(n, 3) == 0) weight = 0.5_r8_kind

    !$omp target teams distribute parallel do collapse(3)
    do k = 1, nz ; do j = jsd, jed ; do i = isd, ied
      t3(i,j,k) = sin(0.1_r8_kind*real(i + 2*j + 3*k + n, r8_kind))
      u3(i,j,k) = cos(0.2_r8_kind*real(i - j + k*n, r8_kind)) / 3.0_r8_kind
    enddo ; enddo ; enddo
    !$omp target teams distribute parallel do collapse(2)
    do j = jsd, jed ; do i = isd, ied
      t2(i,j) = real(n, r8_kind) / 7.0_r8_kind + real(i*j, r8_kind)
      u2(i,j) = real(mod(i + j + n, 5), r8_kind) * 0.1_r8_kind
      if (u2_missing .and. (n == nsteps/2) .and. (i == isc+3) .and. (j == jsc+3)) u2(i,j) = missing
    enddo ; enddo
    !$omp target teams distribute parallel do collapse(3)
    do k = 1, nz ; do j = jsc, jec ; do i = isc, iec
      f4(i,j,k) = real(i + j + k + n, r4_kind) / 9.0_r4_kind
      ! Some points are missing at some times
      if (f4_missing .and. (mod(i + j + n, 7) == 0)) f4(i,j,k) = real(missing, r4_kind)
    enddo ; enddo ; enddo
    if (.not.on_device) then
      !$omp target update from(t3, u3, t2, u2, f4)
    endif

    ! The fields that are only on the host
    do k = 1, nz ; do j = jsd, jed ; do i = isd, ied
      h3(i,j,k) = cos(0.15_r8_kind*real(i - 2*j + 5*k + 2*n, r8_kind)) * 2.0_r8_kind
      l3(i,j,k) = sin(0.05_r8_kind*real(3*i + j - k + n*n, r8_kind)) + 0.5_r8_kind
      ! Values equal to the missing value
      if (mod(i + j + k + n, 11) == 0) l3(i,j,k) = missing
    enddo ; enddo ; enddo
    do j = jsd, jed ; do i = isd, ied
      h2(i,j) = real(mod(i*n + j, 13), r8_kind) - 6.0_r8_kind
      l2(i,j) = real(n, r8_kind) * 0.3_r8_kind - real(abs(i - j), r8_kind)
    enddo ; enddo

    used = send_data(id_t3, t3, Time, is_in=isc-isd+1, js_in=jsc-jsd+1, ks_in=1, ie_in=iec-isd+1, &
                     je_in=jec-jsd+1, ke_in=nz, rmask=mask3, weight=weight, on_device=on_device)
    used = send_data(id_u3, u3, Time, is_in=isc-isd+1, js_in=jsc-jsd+1, ks_in=1, ie_in=iec-isd+1, &
                     je_in=jec-jsd+1, ke_in=nz, rmask=pmask3, on_device=on_device)
    used = send_data(id_t2, t2, Time, is_in=isc-isd+1, ie_in=iec-isd+1, js_in=jsc-jsd+1, je_in=jec-jsd+1, &
                     rmask=mask2, weight=weight, on_device=on_device)
    used = send_data(id_u2, u2, Time, is_in=isc-isd+1, ie_in=iec-isd+1, js_in=jsc-jsd+1, je_in=jec-jsd+1, &
                     on_device=on_device)
    used = send_data(id_f4, f4, Time, weight=real(weight, r4_kind), on_device=on_device)
    used = send_data(id_h3, h3, Time, is_in=isc-isd+1, js_in=jsc-jsd+1, ks_in=1, ie_in=iec-isd+1, &
                     je_in=jec-jsd+1, ke_in=nz, rmask=hmask3, weight=weight, on_device=on_device)
    used = send_data(id_h2, h2, Time, is_in=isc-isd+1, ie_in=iec-isd+1, js_in=jsc-jsd+1, je_in=jec-jsd+1, &
                     rmask=hmask2, weight=weight, on_device=on_device)
    used = send_data(id_l3, l3, Time, is_in=isc-isd+1, js_in=jsc-jsd+1, ks_in=1, ie_in=iec-isd+1, &
                     je_in=jec-jsd+1, ke_in=nz, mask=lmask3, weight=weight, on_device=on_device)
    used = send_data(id_l2, l2, Time, is_in=isc-isd+1, ie_in=iec-isd+1, js_in=jsc-jsd+1, je_in=jec-jsd+1, &
                     mask=lmask2, weight=weight, on_device=on_device)
    call diag_send_complete(Time_step) ! Needed by the modern diag_manager; it does nothing here for the old one
  enddo

  call diag_manager_end(Time)
  !$omp target exit data map(delete: mask3, mask2, t3, u3, t2, u2, f4, stat)
  call fms_end
end program test_diag_on_device
