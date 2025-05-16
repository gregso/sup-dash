module.exports = {
  queryRewrite: (query, { securityContext }) => {
    console.log(`Executing query: ${JSON.stringify(query)}`);
    return query;
  }
};
