## [0.0.14] - 2026-08-14

- Make sure thunks are dethunked in predicate contexts involving blocks or chains of thunks

## [0.0.13] - 2026-08-13

- Calling methods with blocks no longer pre-emptively resolve thunks, avoiding potential deadlocks

## [0.0.12] - 2026-08-10

- Add ractor state to RactorizedObject#inspect

## [0.0.11] - 2026-07-31

- Log if a RactorizedRactor is taken down via ClosedError

## [0.0.10] - 2026-06-30

- Handle thunks being cloned

## [0.0.9] - 2026-06-29

- Fix bug that results from moving Time, which is neither shareable nor movable!
- Handle deadlocks that seem to arise from re-entrant #inspect calls

## [0.0.8] - 2026-06-24

- Add GarbageCollector to close abandoned RactorizedObject ractors and Thunk ractors
- Switch thunks to work off of Ractor instead of Ractor::Port due to port/ractor leaks
- Block on #hash and delegate to super in #==/#!=
- Significant test suite improvements:
  - Remove awkward RACTORIZE_PROC tests and instead use the shmactor gem to get to 100% branch coverage
  - Parallelize the build and run a shmactor build to get full coverage of ractor procs
  - Check for leaked ractors/ports after test suite and fail the build on any memory leaks

## [0.0.7] - 2026-06-06

- Closed Ractor::Ports sometimes give IOError instead of Ractor::ClosedError so handle both

## [0.0.6] - 2026-06-06

- Fix a bug where a closed port mysteriously breaks out of Kernel#loop

## [0.0.5] - 2026-05-30

- Support auto-freezing certain method-arguments
- Support moving method arguments if they are not shareable
- Give ractors a name to help with debugging

## [0.0.4] - 2026-05-23

- Prevent thunks from crossing ractor boundaries
- Create instances of ractorized classes inside the ractor instead of moving them
- Add support for methods that take blocks
- Add #to_s/#inspect to RactorizedObject to help with debugging
- Use #__send__ instead of #send to work with BasicObject

## [0.0.3] - 2026-05-21

- Treat ==, !=, and ! as predicates and delegate them to the ractor (as well as #equal?)
- Don't wrap thunks in more thunks. Unwrap them in RACTOR_PROC which can help with Port#receive issues
- Send a frozen array to the ractor to avoid dup/clone
- Something somewhere in other projects calls Thunk#initialize_clone, so make a placeholder for it
- Do not bother moving shareable objects to the ractor, just send them

## [0.0.2] - 2026-05-18

- Make sure ractorized objects are shareable. This requires them to be unusable after closing (or joining) them.
- Make sure methods don't collide with core methods: #join/#close -> #__join__/#__close__

## [0.0.1] - 2026-04-14

- Initial release

## [0.0.0] - 2026-02-18

- Project birth
