# Export a Hugging Face Marian model to encoder_model.onnx + decoder_model.onnx (no past KV), same IO names as
# Xenova/optimum exports, then int8 dynamic quantization.  usage: python -I marian_export.py <model_dir> <out_prefix>
import sys, os, torch
from transformers import MarianMTModel
from onnxruntime.quantization import quantize_dynamic, QuantType

model_dir, out = sys.argv[1], sys.argv[2]
m = MarianMTModel.from_pretrained(model_dir, torch_dtype=torch.float32).eval()
m.config.use_cache = False

class Enc(torch.nn.Module):
    def __init__(s): super().__init__(); s.e = m.get_encoder()
    def forward(s, input_ids, attention_mask):
        return s.e(input_ids=input_ids, attention_mask=attention_mask).last_hidden_state

class Dec(torch.nn.Module):
    def __init__(s): super().__init__(); s.d = m.model.decoder; s.head = m.lm_head; s.bias = m.final_logits_bias
    def forward(s, input_ids, encoder_hidden_states, encoder_attention_mask):
        h = s.d(input_ids=input_ids, encoder_hidden_states=encoder_hidden_states,
                encoder_attention_mask=encoder_attention_mask, use_cache=False).last_hidden_state
        return s.head(h) + s.bias

ids = torch.tensor([[10, 20, 30, 0]]); am = torch.ones_like(ids)
with torch.no_grad():
    hs = Enc()(ids, am)
    torch.onnx.export(Enc(), (ids, am), f'{out}.encoder.fp32.onnx', input_names=['input_ids', 'attention_mask'],
                      output_names=['last_hidden_state'], opset_version=17, dynamo=False,
                      dynamic_axes={'input_ids': {0: 'b', 1: 's'}, 'attention_mask': {0: 'b', 1: 's'}, 'last_hidden_state': {0: 'b', 1: 's'}})
    dids = torch.tensor([[m.config.decoder_start_token_id, 5]])
    torch.onnx.export(Dec(), (dids, hs, am), f'{out}.decoder.fp32.onnx',
                      input_names=['input_ids', 'encoder_hidden_states', 'encoder_attention_mask'], output_names=['logits'],
                      opset_version=17, dynamo=False,
                      dynamic_axes={'input_ids': {0: 'b', 1: 't'}, 'encoder_hidden_states': {0: 'b', 1: 's'},
                                    'encoder_attention_mask': {0: 'b', 1: 's'}, 'logits': {0: 'b', 1: 't'}})
for part in ('encoder', 'decoder'):
    quantize_dynamic(f'{out}.{part}.fp32.onnx', f'{out}.{part}.int8.onnx', weight_type=QuantType.QInt8,
                     per_channel=True, reduce_range=False, op_types_to_quantize=['MatMul', 'Gather'])
    print(part, os.path.getsize(f'{out}.{part}.fp32.onnx'), '->', os.path.getsize(f'{out}.{part}.int8.onnx'))
