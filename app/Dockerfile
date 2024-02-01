FROM python:3.12-slim

RUN apt update && apt install -y curl

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY src src
COPY start.sh start.sh

CMD [ "./start.sh" ]