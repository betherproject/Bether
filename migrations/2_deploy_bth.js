var BTH = artifacts.require("./BTH.sol");

module.exports = function (deployer) {
  let genesis = 4000000
  let subsidyHalvingInterval = 210000
  let maxHalvings = 64

  let bthFoundationMembers = [
    "0x6AA6161B17845901Cb326A3601b2e9e2D4275520",
    "0x417ea26f1c241Ca53DFdBE19f1040786E3946086",
    "0xBCB86C7dF6E896D028E5DcC0f57925D3636e25E8"
  ]

  let required = 3
  let bthFoundationWallet = "0xB4e63046001074B223872137174EeC63A7e12Cf5"

  deployer.deploy(BTH, bthFoundationMembers, required, bthFoundationWallet, genesis, subsidyHalvingInterval, maxHalvings)
};
