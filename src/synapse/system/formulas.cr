# https://www.desmos.com/calculator/bk3g3l6txg
def fmessage_amount(strength : Float)
  if strength <= 80
    1.8256 * Math.log(strength)
  elsif strength <= 150
    6/1225 * (strength - 80)**2 + 8
  else
    8 * Math.log(strength - 95.402)
  end
end

def fmessage_amount_to_strength(amount : Float)
  if amount < 8
    Math::E**((625 * amount)/1141)
  elsif amount < 32
    (35 * Math.sqrt(amount - 8))/Math.sqrt(6) + 80
  else
    Math::E**(amount/8) + 47701/500
  end
end

def fmessage_lifespan_ms(strength : Float)
  if strength <= 155
    2000 * Math::E**(-strength/60)
  elsif strength <= 700
    Math::E**(strength/100) + 146
  else
    190 * Math.log(strength)
  end
end

def fmessage_lifespan_ms_to_strength(lifespan_ms : Float)
  if lifespan_ms <= 151
    60 * Math.log(2000/lifespan_ms)
  elsif lifespan_ms <= 1242
    100 * Math.log(lifespan_ms - 146)
  else
    Math::E**(lifespan_ms/190)
  end
end

def fmagn_to_flow_scale(magn : Float)
  if 3.684 <= magn
    50/magn
  elsif magn > 0
    magn**2
  else
    0
  end
end

def fmessage_strength_to_jitter(strength : Float)
  if strength.in?(0.0..1000.0)
    1 - (1/1000 * strength**2)/1000
  else
    0.0
  end
end
