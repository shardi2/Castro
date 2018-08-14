subroutine amrex_probinit (init,name,namlen,problo,probhi) bind(c)

  use probdata_module
  use prob_params_module, only : center
  use amrex_error_module
  use eos_type_module, only: eos_t, eos_input_rt, eos_input_rp
  use eos_module, only: eos
  use amrex_fort_module, only : rt => amrex_real
  use amrex_constants_module, only : TWO, M_PI, ZERO, ONE, M_SQRT_2, HALF

  implicit none

  integer, intent(in) :: init, namlen
  integer, intent(in) :: name(namlen)
  real(rt), intent(in) :: problo(3), probhi(3)

  integer :: untin, i

  type(eos_t) :: eos_state

  namelist /fortin/ p_0, u_x, u_y, u_z, rho_0, rhoe_0, frac, &
       B_x, B_y, B_z, T_0, idir

  ! Build "probin" filename -- the name of file containing fortin namelist.
  integer, parameter :: maxlen = 256
  character :: probin*(maxlen)

  if (namlen .gt. maxlen) then
     call amrex_error('probin file name too long')
  end if

  do i = 1, namlen
     probin(i:i) = char(name(i))
  end do

  ! set namelist defaults
  rho_0 = ONE       !density (g/cc)
  u_x = ZERO        !velocity (cm/s)
  u_y = ZERO
  u_z = ZERO
  p_0 = ONE         ! pressure (erg/cc)
  B_x  = ONE/M_SQRT_2
  B_y  = ONE/M_SQRT_2
  B_z  = ZERO


  idir = 1                ! direction across which to jump
  frac = 0.5              ! fraction of the domain for the interface

  ! set local variable defaults
  center(1) = HALF*(problo(1) + probhi(1))
  center(2) = HALF*(problo(2) + probhi(2))
  center(3) = HALF*(problo(3) + probhi(3))

  ! Read namelists
  open(newunit=untin, file=probin(1:namlen), form='formatted', status='old')
  read(untin,fortin)
  close(unit=untin)

  xn_zone(:) = ZERO
  xn_zone(1) = ONE

  ! compute the internal energy (erg/cc) 
  eos_state%rho = rho_0
  eos_state%p = p_0
  eos_state%T = 100.e0_rt  ! initial guess
  eos_state%xn(:) = xn_zone(:)

  call eos(eos_input_rp, eos_state)

  rhoe_0 = rho_0*eos_state%e
  T_0 = eos_state%T

  end subroutine amrex_probinit


! ::: -----------------------------------------------------------
! ::: This routine is called at problem setup time and is used
! ::: to initialize data on each grid.
! :::
! ::: NOTE:  all arrays have one cell of ghost zones surrounding
! :::        the grid interior.  Values in these cells need not
! :::        be set here.
! :::
! ::: INPUTS/OUTPUTS:
! :::
! ::: level     => amr level of grid
! ::: time      => time at which to init data
! ::: lo,hi     => index limits of grid interior (cell centered)
! ::: nstate    => number of state components.  You should know
! :::		   this already!
! ::: state     <=  Scalar array
! ::: delta     => cell size
! ::: xlo,xhi   => physical locations of lower left and upper
! :::              right hand corner of grid.  (does not include
! :::		   ghost region).
! ::: -----------------------------------------------------------
subroutine ca_initdata(level,time,lo,hi,nscal, &
                       state,state_l1,state_l2,state_l3,state_h1,state_h2,state_h3, &
                       delta,xlo,xhi)

  use probdata_module
  use meth_params_module , only: NVAR, URHO, UMX, UMY, UMZ, UEDEN, UEINT, UFS, UTEMP
  use prob_params_module, only : center
  use amrex_fort_module, only : rt => amrex_real
  use amrex_constants_module, only : TWO, M_PI, ZERO, ONE
  use network, only : nspec

  implicit none

  integer :: level, nscal
  integer :: lo(3), hi(3)
  integer :: state_l1,state_l2,state_l3,state_h1,state_h2,state_h3
  real(rt) :: xlo(3), xhi(3), time, delta(3)
  real(rt) :: state(state_l1:state_h1, &
                    state_l2:state_h2, &
                    state_l3:state_h3,NVAR)

  
  real(rt) :: xcen, ycen, zcen, pert
  integer :: i,j,k

  do k = lo(3), hi(3)
     zcen = xlo(3) + delta(3)*(float(k-lo(3)) + 0.5e0_rt)

     do j = lo(2), hi(2)
        ycen = xlo(2) + delta(2)*(float(j-lo(2)) + 0.5e0_rt)

        do i = lo(1), hi(1)
           xcen = xlo(1) + delta(1)*(float(i-lo(1)) + 0.5e0_rt)

           if (idir == 1) then
        
                 state(i,j,k,URHO) = rho_0
                 state(i,j,k,UMX) = u_x
                 state(i,j,k,UMY) = u_y

                 pert = 1.0e-5_rt*sin(TWO*M_PI*xcen)

                 state(i,j,k,UMZ) = (u_z - pert) * rho_0
                 state(i,j,k,UEDEN) = rhoe_0 + 0.5e0_rt*rho_0 * pert**2 + 0.5e0_rt * (B_x**2 + B_y**2 + pert**2)
                 state(i,j,k,UEINT) = rhoe_0
                 state(i,j,k,UTEMP) = T_0
              
           endif

!              state(i,j,k,UFS:UFS-1+nspec) = 0.0e0_rt
              state(i,j,k,UFS  ) = state(i,j,k,URHO)

        enddo
     enddo
  enddo

 end subroutine ca_initdata


! :::
! ::: --------------------------------------------------------------------
! ::: 
subroutine ca_initmag(level, time, lo, hi, &
                      nbx, mag_x, bx_lo, bx_hi, &
                      nby, mag_y, by_lo, by_hi, &
                      nbz, mag_z, bz_lo, bz_hi, &
                      delta, xlo, xhi)

  use probdata_module
  use prob_params_module, only : center
  use amrex_fort_module, only : rt => amrex_real
  use amrex_constants_module, only : TWO, M_PI, ZERO, ONE, M_SQRT_2
 
  implicit none
  
  integer :: level, nbx, nby, nbz
  integer :: lo(3), hi(3)
  integer :: bx_lo(3), bx_hi(3)
  integer :: by_lo(3), by_hi(3)
  integer :: bz_lo(3), bz_hi(3)
  real(rt) :: xlo(3), xhi(3), time, delta(3)

  real(rt) :: mag_x(bx_lo(1):bx_hi(1), bx_lo(2):bx_hi(2), bx_lo(3):bx_hi(3), nbx)
  real(rt) :: mag_y(by_lo(1):by_hi(1), by_lo(2):by_hi(2), by_lo(3):by_hi(3), nby)
  real(rt) :: mag_z(bz_lo(1):bz_hi(1), bz_lo(2):bz_hi(2), bz_lo(3):bz_hi(3), nbz)

  real(rt) :: xcen, ycen, zcen
  integer  :: i, j, k
  
  print *, "Initializing magnetic field!!"

  if (idir .eq. 1) then
     do k = lo(3), hi(3)
        do j = lo(2), hi(2)
           do i = lo(1), hi(1)+1
             
                 mag_x(i,j,k,1) = B_x
           enddo
        enddo
     enddo

     do k = lo(3), hi(3)
        do j = lo(2), hi(2)+1
           do i = lo(1), hi(1)

                 mag_y(i,j,k,1) = B_y
         
           enddo
        enddo
     enddo

     do k = lo(3), hi(3)+1
        do j = lo(2), hi(2)
           do i = lo(1), hi(1)
              xcen = xlo(1) + delta(1)*(float(i-lo(1)) + 0.5d0)
              
              mag_z(i,j,k,1) = 1.0e-5_rt*sin(TWO*M_PI*xcen)

           enddo
        enddo
     enddo

  endif




end subroutine ca_initmag
