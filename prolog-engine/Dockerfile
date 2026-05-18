FROM swipl:stable
WORKDIR /prolog-engine
COPY data/generated/ ./data/generated/
COPY queries/        ./queries/
COPY server.pl       ./server.pl
EXPOSE 8080
CMD ["swipl", "server.pl"]
