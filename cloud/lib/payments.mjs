import Stripe from 'stripe';
import {Fault} from './platform.mjs';

export function payments(env,db, subscription = (client,id)=>client.subscriptions.retrieve(id)) {
  function client(){
    if(env.BILLING_ENABLED!=='true'||!env.STRIPE_SECRET_KEY||!env.STRIPE_PRICE_ID||!/^https:\/\/[a-z0-9.-]+$/.test(env.PUBLIC_ORIGIN||''))throw new Fault('billing_unavailable',503);
    return new Stripe(env.STRIPE_SECRET_KEY,{maxNetworkRetries:0,timeout:7000});
  }
  return {
    async link(uid,portal) {
      const stripe=client();
      let customer=await db.rpc('customer',{p_uid:uid});
      if(!customer) {
        const created=await stripe.customers.create({}, {idempotencyKey:'saytile-customer-'+uid});
        customer=await db.rpc('customer',{p_uid:uid,p_customer:created.id});
      }
      const back=env.PUBLIC_ORIGIN+'/v1/billing-return';
      if(portal)return (await stripe.billingPortal.sessions.create({customer,return_url:back})).url;
      // Never open a second recurring checkout for an already subscribed customer.
      const existing=await stripe.subscriptions.list({customer,status:'all',limit:100});
      if(existing.has_more||existing.data.some(s=>!['canceled','incomplete_expired'].includes(s.status)))throw new Fault('use_billing_portal',409);
      return (await stripe.checkout.sessions.create({customer,mode:'subscription',line_items:[{price:env.STRIPE_PRICE_ID,quantity:1}],success_url:back,cancel_url:back},
        {idempotencyKey:'saytile-checkout-'+uid+'-'+Math.floor(Date.now()/1800000)})).url;
    },
    async webhook(raw,signature) {
      const stripe=client();
      if(!env.STRIPE_WEBHOOK_SECRET)throw new Fault('billing_unavailable',503);
      let event;
      try {event=stripe.webhooks.constructEvent(raw,signature,env.STRIPE_WEBHOOK_SECRET)}catch{throw new Fault('invalid_signature',401)}
      if(event.livemode !== /^(sk|rk)_live_/.test(env.STRIPE_SECRET_KEY))throw new Fault('billing_environment');
      const obj=event.data.object;
      if(event.type==='invoice.paid') {
        const sub=obj.parent?.subscription_details?.subscription;
        const line=obj.lines?.data?.find(l=>l.pricing?.price_details?.price===env.STRIPE_PRICE_ID && l.quantity===1 && l.amount>0);
        if(!sub||!line||obj.status!=='paid'||obj.amount_paid<=0)return;
        const current=await subscription(stripe,sub);
        if(current.customer!==obj.customer||!['active','trialing'].includes(current.status)||
           !current.items.data.some(i=>i.price.id===env.STRIPE_PRICE_ID))return;
        const quota=Number(env.STRIPE_PERIOD_MS);
        if(!Number.isSafeInteger(quota)||quota<35000)throw new Fault('plan_unconfigured',503);
        await db.rpc('invoice',{p_customer:obj.customer,p_subscription:sub,p_invoice:obj.id,p_ms:quota,p_until:new Date(line.period.end*1000).toISOString()});
      } else if(event.type==='customer.subscription.deleted' || event.type==='customer.subscription.updated' && ['unpaid','incomplete_expired'].includes(obj.status)){
        await db.rpc('revoke_subscription',{p_customer:obj.customer,p_subscription:obj.id,p_event:event.id});
      } else if(event.type==='charge.refunded'||event.type==='charge.dispute.created') {
        const charge=event.type==='charge.refunded'?obj:await stripe.charges.retrieve(obj.charge);
        if(charge.customer)await db.rpc('billing_hold',{p_customer:charge.customer,p_event:event.id});
      }
    }
  };
}
