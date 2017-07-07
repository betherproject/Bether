module.exports = {
  networks: {
    development: {
      host: "localhost",
      port: 8545,
      network_id: "*", // Match any network id
    },
    live: {
      network_id: 1,
      host: "localhost",
      port: 8545,
      from: "0xEDd693d95E33B65aE8914db2d6D88Fd7a2A5D9c2",
      gasPrice: 20000000000
    }
  }
};
