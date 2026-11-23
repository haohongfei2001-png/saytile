import {gateway} from './lib/gateway.mjs';
gateway().listen(Number(process.env.PORT||3000),'127.0.0.1');
