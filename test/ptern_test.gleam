import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn two_plus_two_test() {
  { 2 + 2 }
  |> should.equal(4)
}
